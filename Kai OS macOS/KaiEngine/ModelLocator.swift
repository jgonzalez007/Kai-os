//
//  ModelLocator.swift
//  Kai OS macOS
//
//  Find local models on disk
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation

/// ModelLocator — scans the filesystem for available AI models
public final class ModelLocator {
    
    public static let shared = ModelLocator()
    
    private let modelDirectories: [URL]
    
    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        
        self.modelDirectories = [
            caches.appendingPathComponent("Kai/Models"),
            appSupport.appendingPathComponent("Kai/Models"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Models")
        ]
    }
    
    /// Find a model by identifier
    /// - Parameter identifier: Model identifier (e.g., "gemma-4b-it")
    /// - Returns: Absolute path to the model file, or nil if not found
    public func localModelPath(for identifier: String) -> String? {
        let extensions = [".model", ".mlmodel", ".gguf", ".onnx"]
        
        for directory in modelDirectories {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { continue }
            
            for url in contents {
                for ext in extensions {
                    if url.lastPathComponent.hasPrefix(identifier) && url.lastPathComponent.hasSuffix(ext) {
                        return url.path
                    }
                    // Also check if identifier is in the path
                    if url.path.contains(identifier) {
                        return url.path
                    }
                }
            }
        }
        
        return nil
    }
    
    /// List all available models on disk
    public func listAvailableModels() -> [ModelDiscovery] {
        var models: [ModelDiscovery] = []
        let extensions = [".model", ".mlmodel", ".gguf", ".onnx"]
        
        for directory in modelDirectories {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey]
            ) else { continue }
            
            for url in contents {
                let ext = url.pathExtension
                guard extensions.contains(ext) else { continue }
                
                let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                
                models.append(ModelDiscovery(
                    path: url.path,
                    filename: url.lastPathComponent,
                    extension: ext,
                    sizeBytes: Int64(size ?? 0),
                    directory: directory.lastPathComponent
                ))
            }
        }
        
        return models
    }
    
    /// Check if any models are available at all
    public func hasAnyModels() -> Bool {
        return !listAvailableModels().isEmpty
    }
}

/// Discovery result for a model found on disk
public struct ModelDiscovery: CustomStringConvertible {
    public let path: String
    public let filename: String
    public let `extension`: String
    public let sizeBytes: Int64
    public let directory: String
    
    public var description: String {
        return "Model(\(filename), \(sizeBytes) bytes, dir: \(directory))"
    }
}
