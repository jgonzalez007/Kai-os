//
//  KaiOllamaClient.swift
//  Kai OS
//
//  Streams chat replies from a local Ollama server, so conversations stay on this Mac.
//

import Foundation

/// A JSON value inside a tool call's arguments.
public enum KaiToolArgument: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case other

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Accepts a numeric string too, because models sometimes quote numbers.
    public var intValue: Int? {
        switch self {
        case .number(let value): return Int(value)
        case .string(let value): return Int(value)
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .other
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .other: try container.encodeNil()
        }
    }
}

public struct KaiOllamaToolCall: Codable, Equatable, Sendable {
    public let name: String
    public let arguments: [String: KaiToolArgument]

    public init(name: String, arguments: [String: KaiToolArgument]) {
        self.name = name
        self.arguments = arguments
    }

    private struct Function: Codable {
        let name: String
        let arguments: [String: KaiToolArgument]?
    }
    private enum CodingKeys: String, CodingKey { case function }

    public init(from decoder: Decoder) throws {
        let function = try decoder.container(keyedBy: CodingKeys.self).decode(Function.self, forKey: .function)
        name = function.name
        arguments = function.arguments ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Function(name: name, arguments: arguments), forKey: .function)
    }
}

public struct KaiOllamaMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String
    public let toolCalls: [KaiOllamaToolCall]?
    public let toolName: String?
    /// Encoded as base64 strings, which is the form Ollama expects.
    public let images: [Data]?

    private enum CodingKeys: String, CodingKey {
        case role, content, images
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
    }

    public init(role: String, content: String, toolCalls: [KaiOllamaToolCall]? = nil, toolName: String? = nil, images: [Data]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolName = toolName
        self.images = images
    }
}

public struct KaiOllamaModelInfo: Equatable, Sendable {
    public let name: String
    public let supportsVision: Bool

    public init(name: String, supportsVision: Bool) {
        self.name = name
        self.supportsVision = supportsVision
    }
}

public struct KaiOllamaTool: Encodable, Sendable {
    public struct Parameter: Sendable {
        public let name: String
        public let type: String
        public let description: String
        public let required: Bool

        public init(name: String, type: String, description: String, required: Bool) {
            self.name = name
            self.type = type
            self.description = description
            self.required = required
        }
    }

    public let name: String
    public let description: String
    public let parameters: [Parameter]

    public init(name: String, description: String, parameters: [Parameter]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    private struct Property: Encodable {
        let type: String
        let description: String
    }
    private struct Schema: Encodable {
        let type = "object"
        let properties: [String: Property]
        let required: [String]
    }
    private struct Function: Encodable {
        let name: String
        let description: String
        let parameters: Schema
    }
    private enum CodingKeys: String, CodingKey { case type, function }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("function", forKey: .type)
        let schema = Schema(
            properties: Dictionary(uniqueKeysWithValues: parameters.map {
                ($0.name, Property(type: $0.type, description: $0.description))
            }),
            required: parameters.filter(\.required).map(\.name)
        )
        try container.encode(Function(name: name, description: description, parameters: schema), forKey: .function)
    }
}

public struct KaiOllamaChunk: Equatable, Sendable {
    public let content: String
    public let done: Bool
    public let toolCalls: [KaiOllamaToolCall]

    public init(content: String, done: Bool, toolCalls: [KaiOllamaToolCall] = []) {
        self.content = content
        self.done = done
        self.toolCalls = toolCalls
    }
}

public enum KaiOllamaEvent: Equatable, Sendable {
    case text(String)
    case toolCalls([KaiOllamaToolCall])
}

public enum KaiOllamaError: LocalizedError, Equatable, Sendable {
    case unreachable(String)
    case noChatModel
    case http(status: Int, message: String)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let address):
            return "Can't reach Ollama at \(address). Start Ollama, then try again."
        case .noChatModel:
            return "Ollama has no chat model installed. Run `ollama pull <model>`, then try again."
        case .http(let status, let message):
            return "Ollama returned HTTP \(status): \(message)"
        case .server(let message):
            return "Ollama reported an error: \(message)"
        }
    }
}

public struct KaiOllamaClient: Sendable {
    public let baseURL: URL

    public init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
    }

    // MARK: Requests

    /// Thinking is disabled because the chat UI shows only the final answer.
    func chatRequest(model: String, messages: [KaiOllamaMessage], tools: [KaiOllamaTool] = []) throws -> URLRequest {
        struct Body: Encodable {
            let model: String
            let messages: [KaiOllamaMessage]
            let stream: Bool
            let think: Bool
            let tools: [KaiOllamaTool]?
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Long enough for a large model to load into memory before its first token.
        request.timeoutInterval = 300
        request.httpBody = try JSONEncoder().encode(
            Body(model: model, messages: messages, stream: true, think: false, tools: tools.isEmpty ? nil : tools)
        )
        return request
    }

    // MARK: Parsing

    static func parseStreamLine(_ line: String) throws -> KaiOllamaChunk? {
        struct Line: Decodable {
            struct Message: Decodable {
                let content: String?
                let toolCalls: [KaiOllamaToolCall]?
                enum CodingKeys: String, CodingKey {
                    case content
                    case toolCalls = "tool_calls"
                }
            }
            let message: Message?
            let done: Bool?
            let error: String?
        }
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let decoded = try JSONDecoder().decode(Line.self, from: Data(line.utf8))
        if let error = decoded.error { throw KaiOllamaError.server(error) }
        return KaiOllamaChunk(
            content: decoded.message?.content ?? "",
            done: decoded.done ?? false,
            toolCalls: decoded.message?.toolCalls ?? []
        )
    }

    /// Older Ollama versions omit `capabilities`, so a model without the field is kept and
    /// assumed to handle images. If it can't, Ollama reports that when the image is sent.
    static func parseChatModelInfo(_ data: Data) throws -> [KaiOllamaModelInfo] {
        struct Tags: Decodable {
            struct Model: Decodable {
                let name: String
                let capabilities: [String]?
            }
            let models: [Model]
        }
        return try JSONDecoder().decode(Tags.self, from: data).models
            .filter { $0.capabilities?.contains("completion") ?? true }
            .map { KaiOllamaModelInfo(name: $0.name, supportsVision: $0.capabilities?.contains("vision") ?? true) }
    }

    static func parseChatModels(_ data: Data) throws -> [String] {
        try parseChatModelInfo(data).map(\.name)
    }

    // MARK: Network

    public func listChatModels() async throws -> [KaiOllamaModelInfo] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                throw KaiOllamaError.http(status: status, message: String(decoding: data, as: UTF8.self))
            }
            return try Self.parseChatModelInfo(data)
        } catch let error as URLError {
            throw mapped(error)
        }
    }

    /// Yields reply text and tool calls as they arrive. Cancelling the consuming task cancels the request.
    public func streamChat(
        model: String,
        messages: [KaiOllamaMessage],
        tools: [KaiOllamaTool] = []
    ) -> AsyncThrowingStream<KaiOllamaEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatRequest(model: model, messages: messages, tools: tools)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw KaiOllamaError.http(status: status, message: Self.errorMessage(fromBody: body))
                    }
                    for try await line in bytes.lines {
                        guard let chunk = try Self.parseStreamLine(line) else { continue }
                        if !chunk.content.isEmpty { continuation.yield(.text(chunk.content)) }
                        if !chunk.toolCalls.isEmpty { continuation.yield(.toolCalls(chunk.toolCalls)) }
                        if chunk.done { break }
                    }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: error.code == .cancelled ? CancellationError() : mapped(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func mapped(_ error: URLError) -> Error {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
            return KaiOllamaError.unreachable(baseURL.absoluteString)
        default:
            return error
        }
    }

    private static func errorMessage(fromBody body: String) -> String {
        struct ErrorBody: Decodable { let error: String }
        return (try? JSONDecoder().decode(ErrorBody.self, from: Data(body.utf8)).error) ?? body
    }
}
