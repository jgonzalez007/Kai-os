//
//  KaiShared.swift
//  Kai Shared
//
//  Shared types and protocol for local + cloud LLM backends.
//  This module depends only on Foundation.
//

import Foundation

// MARK: - Shared Types (moved from KaiLocalAI)

public enum KaiToolArgument: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case other

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

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
    public let images: [Data]?

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
    public let maxTokens: Int?

    public init(name: String, supportsVision: Bool = true, maxTokens: Int? = nil) {
        self.name = name
        self.supportsVision = supportsVision
        self.maxTokens = maxTokens
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

// MARK: - Protocol

/// Protocol that all chat clients must implement.
public protocol KaiChatClient: Sendable {
    var providerName: String { get }
    var needsApiKey: Bool { get }
    func listModels() async throws -> [KaiOllamaModelInfo]
    func stream(model: String, messages: [KaiOllamaMessage], tools: [KaiOllamaTool]?, temperature: Double?) -> AsyncThrowingStream<KaiOllamaEvent, Error>
}

// MARK: - Service

/// Manages multiple chat clients and routes requests.
public final class KaiChatService: Sendable {
    private var ollama: (any KaiChatClient)?
    private var clients: [String: any KaiChatClient] = [:]
    public var selectedProvider: String = "ollama"
    public var allModels: [KaiOllamaModelInfo] = []

    public init(ollama: (any KaiChatClient)?) {
        self.ollama = ollama
    }

    public func register(_ client: any KaiChatClient, for key: String) {
        clients[key] = client
    }

    public func activeClient() -> (any KaiChatClient)? {
        switch selectedProvider {
        case "openai": return clients["openai"]
        case "anthropic": return clients["anthropic"]
        default: return ollama
        }
    }

    public func hasApiKey(for provider: String) -> Bool {
        let key = "kai.\(provider).apiKey"
        return UserDefaults.standard.string(forKey: key) != nil
    }

    public func refreshModels() async {
        var models: [KaiOllamaModelInfo] = []
        for (key, client) in clients {
            if hasApiKey(for: key) {
                do {
                    let cloudModels = try await client.listModels()
                    models.append(contentsOf: cloudModels.map {
                        KaiOllamaModelInfo(name: "\(key):\($0.name)", supportsVision: $0.supportsVision)
                    })
                } catch { /* Provider unavailable */ }
            }
        }
        allModels = models
    }

    public func rawModelName(_ model: String) -> String {
        if model.hasPrefix("ollama:") { return String(model.dropFirst(7)) }
        if model.hasPrefix("openai:") { return String(model.dropFirst(7)) }
        if model.hasPrefix("anthropic:") { return String(model.dropFirst(10)) }
        return model
    }

    public func stream(model: String, messages: [KaiOllamaMessage], tools: [KaiOllamaTool]?, temperature: Double? = nil) -> AsyncThrowingStream<KaiOllamaEvent, Error> {
        let rawModel = rawModelName(model)
        guard let client = activeClient() else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: KaiOllamaError.unreachable("No chat client available."))
            }
        }
        return client.stream(model: rawModel, messages: messages, tools: tools, temperature: temperature)
    }
}



// MARK: - Extension Helpers

extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard self.hasPrefix(prefix) else { return nil }
        return String(self.dropFirst(prefix.count))
    }
}
