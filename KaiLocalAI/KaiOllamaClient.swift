//
//  KaiOllamaClient.swift
//  Kai OS
//
//  Streams chat replies from a local Ollama server, so conversations stay on this Mac.
//

import Foundation

public struct KaiOllamaMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct KaiOllamaChunk: Equatable, Sendable {
    public let content: String
    public let done: Bool

    public init(content: String, done: Bool) {
        self.content = content
        self.done = done
    }
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
    func chatRequest(model: String, messages: [KaiOllamaMessage]) throws -> URLRequest {
        struct Body: Encodable {
            let model: String
            let messages: [KaiOllamaMessage]
            let stream: Bool
            let think: Bool
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Long enough for a large model to load into memory before its first token.
        request.timeoutInterval = 300
        request.httpBody = try JSONEncoder().encode(
            Body(model: model, messages: messages, stream: true, think: false)
        )
        return request
    }

    // MARK: Parsing

    static func parseStreamLine(_ line: String) throws -> KaiOllamaChunk? {
        struct Line: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
            let done: Bool?
            let error: String?
        }
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let decoded = try JSONDecoder().decode(Line.self, from: Data(line.utf8))
        if let error = decoded.error { throw KaiOllamaError.server(error) }
        return KaiOllamaChunk(content: decoded.message?.content ?? "", done: decoded.done ?? false)
    }

    /// Older Ollama versions omit `capabilities`, so a model without the field is kept.
    static func parseChatModels(_ data: Data) throws -> [String] {
        struct Tags: Decodable {
            struct Model: Decodable {
                let name: String
                let capabilities: [String]?
            }
            let models: [Model]
        }
        return try JSONDecoder().decode(Tags.self, from: data).models
            .filter { $0.capabilities?.contains("completion") ?? true }
            .map(\.name)
    }

    // MARK: Network

    public func listChatModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                throw KaiOllamaError.http(status: status, message: String(decoding: data, as: UTF8.self))
            }
            return try Self.parseChatModels(data)
        } catch let error as URLError {
            throw mapped(error)
        }
    }

    /// Yields reply text as it arrives. Cancelling the consuming task cancels the request.
    public func streamChat(model: String, messages: [KaiOllamaMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatRequest(model: model, messages: messages)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw KaiOllamaError.http(status: status, message: Self.errorMessage(fromBody: body))
                    }
                    for try await line in bytes.lines {
                        guard let chunk = try Self.parseStreamLine(line) else { continue }
                        if !chunk.content.isEmpty { continuation.yield(chunk.content) }
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
