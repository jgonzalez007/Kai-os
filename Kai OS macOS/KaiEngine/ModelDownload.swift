//
//  ModelDownload.swift
//  Kai OS macOS
//
//  Download models on demand
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Model metadata for download tracking
public struct ModelInfo: Codable {
    public let identifier: String
    public let url: String
    public let sizeBytes: Int64
    public let sha256: String
    public let type: ModelType
    
    public enum ModelType: String, Codable {
        case gemma4
        case qwen7b
        case qwen3b
    }
}

/// ModelDownload — handles downloading and verifying AI models
public final class ModelDownload {
    
    public static let shared = ModelDownload()
    
    /// Download progress callbacks
    public var progressHandler: ((String, Double) -> Void)?
    public var completionHandler: ((String, Result<Void, Error>) -> Void)?
    
    private let downloadsDir: URL
    private var activeDownloads: [String: DownloadState] = [:]
    
    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.downloadsDir = caches.appendingPathComponent("Kai/Models")
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    }
    
    /// Known models and their download URLs
    public func knownModels() -> [ModelInfo] {
        return [
            ModelInfo(
                identifier: "gemma-4b-it",
                url: "https://huggingface.co/google/gemma-4b-it/resolve/main/model.metal",
                sizeBytes: 8_500_000_000,
                sha256: "",
                type: .gemma4
            ),
            ModelInfo(
                identifier: "qwen-7b-it",
                url: "https://huggingface.co/Qwen/Qwen2.5-7B-Instruct/resolve/main/model.metal",
                sizeBytes: 15_200_000_000,
                sha256: "",
                type: .qwen7b
            ),
            ModelInfo(
                identifier: "qwen-3b",
                url: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct/resolve/main/model.metal",
                sizeBytes: 6_100_000_000,
                sha256: "",
                type: .qwen3b
            )
        ]
    }
    
    /// Start downloading a model
    public func startDownload(modelInfo: ModelInfo) async {
        let id = modelInfo.identifier
        activeDownloads[id] = DownloadState(progress: 0, completed: false, error: nil)
        
        guard let url = URL(string: modelInfo.url) else {
            activeDownloads[id]?.error = ModelDownloadError.invalidURL
            activeDownloads[id]?.completed = true

            return
        }
        
        let localPath = downloadsDir.appendingPathComponent("\(id).model")
        
        do {
            let (fileURL, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: fileURL, to: localPath)
            
            activeDownloads[id]?.progress = 1.0
            activeDownloads[id]?.completed = true
            
            progressHandler?(id, 1.0)
            completion?(id, .success(()))
        } catch {
            activeDownloads[id]?.error = error
            activeDownloads[id]?.completed = true
            progressHandler?(id, 0.0)
            completion?(id, .failure(error))
        }
    }
    
    /// Check if a model is fully downloaded
    public func isModelDownloaded(_ identifier: String) -> Bool {
        let path = downloadsDir.appendingPathComponent("\(identifier).model")
        return FileManager.default.fileExists(atPath: path.path)
    }
    
    /// Delete a downloaded model
    public func deleteModel(_ identifier: String) throws {
        let path = downloadsDir.appendingPathComponent("\(identifier).model")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ModelDownloadError.notFound(identifier)
        }
        try FileManager.default.removeItem(at: path)
    }
    
    /// Total disk space used by downloaded models
    public func totalModelSize() throws -> Int64 {
        let enumerator = FileManager.default.enumerator(
            at: downloadsDir,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        var total: Int64 = 0
        for case let fileURL as URL in (enumerator as? [URL]) ?? [] {
            let size: Int = { try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 }() ?? 0
            total += Int64(size)
        }
        return total
    }
    
    private var progress: ((String, Double) -> Void)? {
        return progressHandler
    }
    private var completion: ((String, Result<Void, Error>) -> Void)? {
        return completionHandler
    }
    
    private struct DownloadState {
        var progress: Double
        var completed: Bool
        var error: Error?
    }
}

public enum ModelDownloadError: Error, LocalizedError {
    case invalidURL
    case downloadFailed(String)
    case notFound(String)
    case corrupted(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid download URL"
        case .downloadFailed(let name): return "Failed to download: \(name)"
        case .notFound(let name): return "Model not found: \(name)"
        case .corrupted(let name): return "Model corrupted: \(name)"
        }
    }
}
