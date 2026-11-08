//
//  KaiOllamaSetup.swift
//  Kai Local AI
//
//  What the first-run guide needs to know about Ollama: is it installed, running, does it have a
//  model, and how far a model download has got. Pure logic plus one streaming download call.
//

import Foundation
import KaiShared

public enum KaiOllamaSetup {
    /// The model the guide offers. It handles images and tools, which Kai uses.
    public static let recommendedModel = "gemma4:e4b"

    public enum State: Equatable, Sendable {
        /// Ollama is not on this Mac.
        case notInstalled
        /// Installed, but the server does not answer.
        case notRunning
        /// Running with no chat model.
        case noModel
        case ready(models: [String])
    }

    /// `models` is nil when the server could not be reached.
    public static func evaluate(appInstalled: Bool, models: [String]?) -> State {
        guard let models else { return appInstalled ? .notRunning : .notInstalled }
        return models.isEmpty ? .noModel : .ready(models: models)
    }

    /// Places Ollama's app normally lives.
    public static func appPaths(home: String = NSHomeDirectory()) -> [String] {
        ["/Applications/Ollama.app", home + "/Applications/Ollama.app"]
    }

    public static func isInstalled(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                                   home: String = NSHomeDirectory()) -> Bool {
        appPaths(home: home).contains(where: fileExists)
            || ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"].contains(where: fileExists)
    }

    public static let downloadPage = URL(string: "https://ollama.com/download")!

    /// A model name Kai may pass to `ollama pull`: letters, digits and . _ - : /
    public static func isValidModelName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 120 else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || "._-:/".contains($0) }
            && !name.hasPrefix("-") && !name.contains("..")
    }
}

public struct KaiPullProgress: Equatable, Sendable {
    public let status: String
    public let completed: Int64
    public let total: Int64
    public let isDone: Bool

    /// 0...1, or nil when the size is not known yet.
    public var fraction: Double? {
        total > 0 ? min(1, Double(completed) / Double(total)) : nil
    }

    public var detail: String {
        guard total > 0 else { return status }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "\(status) \(f.string(fromByteCount: completed)) of \(f.string(fromByteCount: total))"
    }
}

extension KaiOllamaClient {
    /// Parses one line of the `/api/pull` stream. Throws the server's own message for an error line.
    static func parsePullLine(_ line: Data) throws -> KaiPullProgress? {
        struct Line: Decodable {
            let status: String?
            let total: Int64?
            let completed: Int64?
            let error: String?
        }
        guard let decoded = try? JSONDecoder().decode(Line.self, from: line) else { return nil }
        if let error = decoded.error { throw KaiOllamaError.server(error) }
        let status = decoded.status ?? ""
        return KaiPullProgress(status: status, completed: decoded.completed ?? 0, total: decoded.total ?? 0, isDone: status == "success")
    }

    /// Downloads a model, yielding progress. Cancelling the consuming task stops the download.
    public func pull(model: String) -> AsyncThrowingStream<KaiPullProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
                    request.timeoutInterval = 60
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                        throw KaiOllamaError.http(status: status, message: "Could not download \(model).")
                    }
                    for try await line in bytes.lines {
                        if let progress = try Self.parsePullLine(Data(line.utf8)) { continuation.yield(progress) }
                    }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: KaiOllamaError.unreachable(baseURL.absoluteString))
                    _ = error
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
