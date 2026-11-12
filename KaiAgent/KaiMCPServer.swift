//
//  KaiMCPServer.swift
//  Kai Agent
//
//  A tiny tool server that lives only for one Claude question. Claude Code connects to it over the loopback
//  network (this Mac only, a one-time password in every request) and calls Kai's own tools: search mail, read a
//  message, search notes, and so on. Kai decides which tools exist, answers each call with its own readers, and
//  shuts the server down when the question is answered. The model never gets a shell, files or a browser of its own.
//

import Foundation
import Network
import KaiShared

public final class KaiMCPServer: @unchecked Sendable {
    public struct Connection: Sendable, Equatable {
        public let name: String
        public let url: String
        public let token: String

        /// The `--mcp-config` JSON that points Claude Code at this server.
        public var configJSON: String {
            let config: [String: Any] = ["mcpServers": [name: ["type": "http", "url": url, "headers": ["Authorization": "Bearer " + token]]]]
            let data = (try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])) ?? Data("{}".utf8)
            return String(decoding: data, as: UTF8.self)
        }
    }

    public typealias CallHandler = @Sendable (KaiOllamaToolCall) async -> String

    public static let maxRequestBytes = 1_000_000
    public static let maxResultCharacters = 12_000

    public let name: String
    private let tools: [KaiOllamaTool]
    private let handler: CallHandler
    private let token: String
    private let queue = DispatchQueue(label: "kai.mcp.server")
    private var listener: NWListener?

    public init(name: String = "kai", tools: [KaiOllamaTool], handler: @escaping CallHandler) {
        self.name = name
        self.tools = tools
        self.handler = handler
        var bytes = [UInt8](repeating: 0, count: 24)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess { bytes = (0..<24).map { _ in UInt8.random(in: 0...255) } }
        token = bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Starting and stopping

    public func start() async throws -> Connection {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue, once.take() { continuation.resume(returning: port) }
                case .failed(let error):
                    if once.take() { continuation.resume(throwing: error) }
                case .cancelled:
                    if once.take() { continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return Connection(name: name, url: "http://127.0.0.1:\(port)/mcp", token: token)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
    }

    // MARK: HTTP

    private final class Buffer: @unchecked Sendable { var data = Data() }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        let buffer = Buffer()
        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { connection.cancel(); return }
                if let data { buffer.data.append(data) }
                if buffer.data.count > Self.maxRequestBytes { connection.cancel(); return }
                switch Self.parse(buffer.data) {
                case .complete(let request):
                    Task {
                        let response = await self.respond(to: request)
                        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                    }
                case .invalid:
                    connection.send(content: Self.http(400, "Bad Request"), completion: .contentProcessed { _ in connection.cancel() })
                case .incomplete:
                    if error == nil, !isComplete { receive() } else { connection.cancel() }
                }
            }
        }
        receive()
    }

    struct Request: Equatable {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data
    }

    enum Parsed: Equatable { case incomplete, invalid, complete(Request) }

    static func parse(_ data: Data) -> Parsed {
        let marker = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: marker) else { return data.count > 16_384 ? .invalid : .incomplete }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxRequestBytes else { return .invalid }
        let bodyStart = end.upperBound
        guard data.count - bodyStart >= length else { return .incomplete }
        return .complete(Request(method: String(first[0]), path: String(first[1]), headers: headers, body: data[bodyStart..<(bodyStart + length)]))
    }

    static func http(_ status: Int, _ reason: String, body: Data = Data()) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !body.isEmpty { head += "Content-Type: application/json\r\n" }
        return Data((head + "\r\n").utf8) + body
    }

    func respond(to request: Request) async -> Data {
        guard request.headers["authorization"] == "Bearer " + token else { return Self.http(401, "Unauthorized") }
        guard request.method == "POST", request.path.hasPrefix("/mcp") else { return Self.http(405, "Method Not Allowed") }
        guard let reply = await Self.handle(request.body, tools: tools, handler: handler) else { return Self.http(202, "Accepted") }
        return Self.http(200, "OK", body: reply)
    }

    // MARK: JSON-RPC

    /// One JSON-RPC message in, the answer out. Nil for a notification, which has no answer.
    static func handle(_ body: Data, tools: [KaiOllamaTool], handler: CallHandler) async -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let method = object["method"] as? String else {
            return reply(id: nil, error: (-32700, "Parse error"))
        }
        guard let id = object["id"] else { return nil }
        let params = object["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return reply(id: id, result: [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-03-26",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "kai", "version": "1"],
            ])
        case "ping":
            return reply(id: id, result: [String: Any]())
        case "tools/list":
            return reply(id: id, result: ["tools": tools.map(describe)])
        case "tools/call":
            guard let name = params["name"] as? String, tools.contains(where: { $0.name == name }) else {
                return reply(id: id, result: content("There is no tool with that name.", isError: true))
            }
            let raw = params["arguments"] as? [String: Any] ?? [:]
            let call = KaiOllamaToolCall(name: name, arguments: raw.mapValues(argument))
            let text = await handler(call)
            return reply(id: id, result: content(String(text.prefix(maxResultCharacters)), isError: false))
        default:
            return reply(id: id, error: (-32601, "Method not found"))
        }
    }

    static func describe(_ tool: KaiOllamaTool) -> [String: Any] {
        var properties: [String: Any] = [:]
        for parameter in tool.parameters { properties[parameter.name] = ["type": parameter.type, "description": parameter.description] }
        return ["name": tool.name, "description": tool.description,
                "inputSchema": ["type": "object", "properties": properties, "required": tool.parameters.filter(\.required).map(\.name)]]
    }

    private static func argument(_ value: Any) -> KaiToolArgument {
        if let value = value as? Bool, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() { return .bool(value) }
        if let value = value as? NSNumber { return .number(value.doubleValue) }
        if let value = value as? String { return .string(value) }
        return .other
    }

    private static func content(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private static func reply(id: Any?, result: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private static func reply(id: Any?, error: (Int, String)) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": error.0, "message": error.1]])
    }
}
