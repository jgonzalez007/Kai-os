//
//  KaiCloudChat.swift
//  Kai Shared
//
//  Chat clients for cloud providers (OpenAI and Anthropic).
//  Conform to KaiChatClient for protocol-based routing.
//

import Foundation
import KaiShared

// MARK: - OpenAI Client

/// Streams replies from OpenAI (ChatGPT) via the Chat Completions API.
/// Conform to KaiChatClient for protocol-based routing.
public final class OpenAIChatClient: KaiChatClient {
    
    public static let baseURL = URL(string: "https://api.openai.com/v1")!
    public static let defaultModel = "gpt-4o"
    
    public var providerName: String { "OpenAI" }
    public var needsApiKey: Bool { true }
    
    public init(apiKey: String? = nil) {
        if let key = apiKey {
            UserDefaults.standard.set(key, forKey: "kai.openai.apiKey")
        }
    }
    
    /// Build OpenAI-format messages from the shared format.
    private func toOpenAIMessages(messages: [KaiOllamaMessage]) -> [[String: Any]] {
        messages.map { msg in
            var dict: [String: Any] = ["role": msg.role, "content": msg.content]
            
            if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                var callEntries: [[String: Any]] = []
                for call in toolCalls {
                    var fn: [String: Any] = ["name": call.name]
                    var args: [String: Any] = [:]
                    for (k, v) in call.arguments {
                        switch v {
                        case .string(let s): args[k] = s
                        case .number(let n): args[k] = n
                        case .bool(let b): args[k] = b
                        default: break
                        }
                    }
                    fn["arguments"] = args
                    callEntries.append(["id": call.name, "type": "function", "function": fn])
                }
                dict["tool_calls"] = callEntries
            }
            
            return dict
        }
    }
    
    /// List available OpenAI models.
    public func listModels() async throws -> [KaiOllamaModelInfo] {
        let apiKey = UserDefaults.standard.string(forKey: "kai.openai.apiKey") ?? ""
        guard !apiKey.isEmpty else { return [] }
        
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let bodyText = String(decoding: data, as: UTF8.self)
            throw KaiOllamaError.http(status: statusCode, message: bodyText)
        }
        
        struct ModelEntry: Decodable { let id: String }
        struct Response: Decodable { let data: [ModelEntry] }
        
        let models = try JSONDecoder().decode(Response.self, from: data)
        
        return models.data.map { model in
            let supportsVision = model.id.contains("4o") || model.id.contains("mini")
                || model.id.contains("vision") || model.id.contains("o1") || model.id.contains("o3")
            return KaiOllamaModelInfo(name: model.id, supportsVision: supportsVision)
        }
    }
    
    /// Stream chat completions from OpenAI.
    public func stream(
        model: String,
        messages: [KaiOllamaMessage],
        tools: [KaiOllamaTool]? = nil,
        temperature: Double? = nil) -> AsyncThrowingStream<KaiOllamaEvent, Error> {
        
        let apiKey = UserDefaults.standard.string(forKey: "kai.openai.apiKey") ?? ""
        guard !apiKey.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: KaiOllamaError.unreachable("OpenAI API key is not set."))
            }
        }
        
        let modelName = model.isEmpty ? Self.defaultModel : model
        let openAIMessages = toOpenAIMessages(messages: messages)
        
        var body: [String: Any] = [
            "model": modelName,
            "messages": openAIMessages,
            "stream": true,
        ]
        
        if let tools {
            body["tools"] = tools.map { tool in
                var props: [String: Any] = [:]
                var required: [String] = []
                for p in tool.parameters {
                    props[p.name] = ["type": p.type, "description": p.description]
                    if p.required { required.append(p.name) }
                }
                return [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": ["type": "object", "properties": props, "required": required],
                    ]
                ]
            }
            body["tool_choice"] = "auto"
        }
        
        if let temp = temperature {
            body["temperature"] = temp
        }
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: Self.baseURL.appendingPathComponent("/chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 300
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if statusCode != 200 {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line }
                        throw KaiOllamaError.http(status: statusCode, message: bodyText)
                    }
                    
                    for try await line in bytes.lines {
                        guard let stripped = line.stripPrefix("data:") else { continue }
                        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed != "[DONE]" else { continue }

                        guard let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let choice = choices.first,
                              let delta = choice["delta"] as? [String: Any],
                              let text = delta["content"] as? String else { continue }
                        
                        continuation.yield(.text(text))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Anthropic Client

/// Client for Anthropic Claude via the Messages API.
public final class AnthropicChatClient: KaiChatClient {
    
    public static let baseURL = URL(string: "https://api.anthropic.com")!
    public static let defaultModel = "claude-sonnet-4-20250514"
    
    public var providerName: String { "Anthropic" }
    public var needsApiKey: Bool { true }
    
    public init(apiKey: String? = nil) {
        if let key = apiKey {
            UserDefaults.standard.set(key, forKey: "kai.anthropic.apiKey")
        }
    }
    
    /// Stream chat completions from Anthropic.
    public func stream(
        model: String,
        messages: [KaiOllamaMessage],
        tools: [KaiOllamaTool]? = nil,
        temperature: Double? = nil) -> AsyncThrowingStream<KaiOllamaEvent, Error> {
        
        let apiKey = UserDefaults.standard.string(forKey: "kai.anthropic.apiKey") ?? ""
        guard !apiKey.isEmpty else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: KaiOllamaError.unreachable("Anthropic API key is not set."))
            }
        }
        
        let modelName = model.isEmpty ? Self.defaultModel : model
        
        // Anthropic uses user/assistant format, no system role at top level
        var anthropicMessages: [[String: Any]] = []
        var systemContent: String?
        
        for msg in messages {
            switch msg.role {
            case "system":
                systemContent = msg.content
            default:
                var dict: [String: Any] = ["role": msg.role, "content": msg.content]
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    var contentBlocks: [[String: Any]] = []
                    for call in toolCalls {
                        var fnInput: [String: Any] = [:]
                        for (k, v) in call.arguments {
                            switch v {
                            case .string(let s): fnInput[k] = s
                            case .number(let n): fnInput[k] = n
                            case .bool(let b): fnInput[k] = b
                            default: break
                            }
                        }
                        contentBlocks.append([
                            "type": "tool_use",
                            "id": call.name,
                            "name": call.name,
                            "input": fnInput
                        ])
                    }
                    dict["content"] = contentBlocks
                }
                anthropicMessages.append(dict)
            }
        }
        
        var body: [String: Any] = [
            "model": modelName,
            "messages": anthropicMessages,
            "max_tokens": 8192,
            "stream": true,
        ]
        
        if let system = systemContent {
            body["system"] = system
        }
        
        if let tools {
            body["tools"] = tools.map { tool in
                var inputSchema: [String: Any] = ["type": "object", "properties": [:] as [String: Any]]
                var required: [String] = []
                for p in tool.parameters {
                    guard var props = inputSchema["properties"] as? [String: Any] else { continue }
                    props[p.name] = ["type": p.type, "description": p.description]
                    inputSchema["properties"] = props
                    if p.required { required.append(p.name) }
                }
                return ["name": tool.name, "input_schema": inputSchema]
            }
        }
        
        if let temp = temperature {
            body["temperature"] = temp
        }
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: Self.baseURL.appendingPathComponent("/v1/messages"))
                    request.httpMethod = "POST"
                    request.setValue("api-key \(apiKey)", forHTTPHeaderField: "x-api-key")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("2024-10-22", forHTTPHeaderField: "anthropic-version")
                    request.timeoutInterval = 300
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    
                    if statusCode != 200 {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line }
                        throw KaiOllamaError.http(status: statusCode, message: bodyText)
                    }
                    
                    for try await line in bytes.lines {
                        guard let stripped = line.stripPrefix("data:") else { continue }
                        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed != "event: ping" else { continue }

                        guard let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
                              let type = json["type"] as? String else { continue }
                        
                        switch type {
                        case "content_block_delta":
                            guard let json2 = json["delta"] as? [String: Any],
                                  let text = json2["text"] as? String else { continue }
                            continuation.yield(.text(text))
                        case "message_stop":
                            continuation.finish()
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    /// List available Anthropic models.
    public func listModels() async throws -> [KaiOllamaModelInfo] {
        let apiKey = UserDefaults.standard.string(forKey: "kai.anthropic.apiKey") ?? ""
        guard !apiKey.isEmpty else { return [] }
        
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("/v1/models"))
        request.httpMethod = "GET"
        request.setValue("api-key \(apiKey)", forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2024-10-22", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            let bodyText = String(decoding: data, as: UTF8.self)
            throw KaiOllamaError.http(status: statusCode, message: bodyText)
        }
        
        struct ModelEntry: Decodable { let id: String }
        struct Response: Decodable { let data: [ModelEntry] }
        
        let models = try JSONDecoder().decode(Response.self, from: data)
        
        return models.data.map { model in
            let supportsVision = model.id.contains("vision") || model.id.contains("sonnet")
                || model.id.contains("opus") || model.id.contains("haiku")
            return KaiOllamaModelInfo(name: model.id, supportsVision: supportsVision)
        }
    }
}
