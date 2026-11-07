import Foundation
import KaiShared

public struct KaiOllamaClient: KaiChatClient {
    public var providerName: String { "Ollama" }
    public var needsApiKey: Bool { false }
    public let baseURL: URL

    public init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
    }

    // MARK: Requests

    /// Thinking is disabled because the chat UI shows only the final answer.
    func chatRequest(model: String, messages: [KaiOllamaMessage], tools: [KaiOllamaTool]? = nil, temperature: Double? = nil, format: String? = nil) throws -> URLRequest {
        struct Options: Encodable { let temperature: Double }
        struct Body: Encodable {
            let model: String
            let messages: [KaiOllamaMessage]
            let stream: Bool
            let think: Bool
            let tools: [KaiOllamaTool]?
            let options: Options?
            let format: String?
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Long enough for a large model to load into memory before its first token.
        request.timeoutInterval = 300
        request.httpBody = try JSONEncoder().encode(
            Body(model: model, messages: messages, stream: true, think: false, tools: tools, options: temperature.map(Options.init), format: format)
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

    public func listModels() async throws -> [KaiOllamaModelInfo] {
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
    public func stream(
        model: String,
        messages: [KaiOllamaMessage],
        tools: [KaiOllamaTool]? = nil,
        temperature: Double? = nil) -> AsyncThrowingStream<KaiOllamaEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatRequest(model: model, messages: messages, tools: tools, temperature: temperature)
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
