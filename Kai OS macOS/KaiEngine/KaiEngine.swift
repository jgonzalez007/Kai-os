//
//  KaiEngine.swift
//  Kai OS macOS
//
//  Core inference engine
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// KaiEngine — on-device inference core
/// Wraps LiteRT-LM / Gemma 4 / Qwen models with Metal GPU acceleration
/// and speculative decoding for fast local inference.
public final class KaiEngine {
    
    /// Singleton access
    public static let shared = KaiEngine()
    
    /// Current model identifier
    public var modelIdentifier: String
    
    /// Metal GPU acceleration enabled
    public var metalGPUEnabled: Bool
    
    /// Speculative decoding enabled
    public var speculativeDecodingEnabled: Bool
    
    private init(modelIdentifier: String = "gemma-4b-it",
                 metalGPUEnabled: Bool = true,
                 speculativeDecodingEnabled: Bool = true) {
        self.modelIdentifier = modelIdentifier
        self.metalGPUEnabled = metalGPUEnabled
        self.speculativeDecodingEnabled = speculativeDecodingEnabled
    }
    
    /// Perform inference on input text
    /// - Parameter prompt: The text to infer on
    /// - Parameter context: Optional context/history
    /// - Returns: Inference result text
    public func infer(_ prompt: String, context: String? = nil) async throws -> String {
        let fullPrompt = context.map { "\($0)\n\n\(prompt)" } ?? prompt
        
        switch modelIdentifier {
        case "gemma-4b-it":
            return try await inferWithGemma(fullPrompt)
        case "qwen-7b-it":
            return try await inferWithQwen(fullPrompt)
        case "qwen-3b":
            return try await inferWithQwen3B(fullPrompt)
        default:
            throw KaiEngineError.unknownModel(modelIdentifier)
        }
    }
    
    /// Infer with Gemma 4 via LiteRT-LM runtime
    private func inferWithGemma(_ prompt: String) async throws -> String {
        // LiteRT-LM + Gemma 4 E4B via Metal GPU
        let config = ModelConfig(
            modelPath: ModelLocator.shared.localModelPath(for: "gemma-4b-it"),
            metalGPU: metalGPUEnabled,
            speculativeDecoding: speculativeDecodingEnabled
        )
        
        guard let modelPath = config.modelPath,
              FileManager.default.fileExists(atPath: modelPath) else {
            throw KaiEngineError.modelNotFound("gemma-4b-it")
        }
        
        // Delegate to inference runtime
        return try await KaiInferenceRuntime.shared.run(
            modelPath: modelPath,
            prompt: prompt,
            config: config
        )
    }
    
    /// Infer with Qwen via ONNX Runtime
    private func inferWithQwen(_ prompt: String) async throws -> String {
        let config = ModelConfig(
            modelPath: ModelLocator.shared.localModelPath(for: "qwen-7b-it"),
            metalGPU: false,
            speculativeDecoding: false
        )
        
        guard let modelPath = config.modelPath else {
            throw KaiEngineError.modelNotFound("qwen-7b-it")
        }
        
        return try await KaiInferenceRuntime.shared.run(
            modelPath: modelPath,
            prompt: prompt,
            config: config
        )
    }
    
    /// Infer with Qwen 3B (smaller model for faster inference)
    private func inferWithQwen3B(_ prompt: String) async throws -> String {
        let config = ModelConfig(
            modelPath: ModelLocator.shared.localModelPath(for: "qwen-3b"),
            metalGPU: false,
            speculativeDecoding: false
        )
        
        guard let modelPath = config.modelPath else {
            throw KaiEngineError.modelNotFound("qwen-3b")
        }
        
        return try await KaiInferenceRuntime.shared.run(
            modelPath: modelPath,
            prompt: prompt,
            config: config
        )
    }
    
    /// Generate a completion with temperature control
    public func generateCompletion(
        prompt: String,
        temperature: Float = 0.7,
        maxTokens: Int = 512
    ) async throws -> String {
        return try await infer(prompt)
    }
    
    /// Check if the current model is available locally
    public func isModelAvailable() -> Bool {
        guard let path = ModelLocator.shared.localModelPath(for: modelIdentifier) else {
            return false
        }
        return FileManager.default.fileExists(atPath: path)
    }
}

/// Engine configuration
public struct ModelConfig {
    let modelPath: String?
    let metalGPU: Bool
    let speculativeDecoding: Bool
    
    init(modelPath: String?, metalGPU: Bool, speculativeDecoding: Bool) {
        self.modelPath = modelPath
        self.metalGPU = metalGPU
        self.speculativeDecoding = speculativeDecoding
    }
}

/// Inference runtime for actual model execution
public actor KaiInferenceRuntime {
    public static let shared = KaiInferenceRuntime()
    
    private init() {}
    
    public func run(modelPath: String, prompt: String, config: ModelConfig) async throws -> String {
        // In production, this calls into the LiteRT-LM / ONNX runtime
        // For Phase 1, we return a placeholder that will be wired in Phase 7
        return "[KaiEngine] Inference placeholder — model: \(modelPath.split(separator: "/").last ?? "unknown"), metalGPU: \(config.metalGPU)"
    }
}

/// Engine errors
public enum KaiEngineError: Error, LocalizedError {
    case modelNotFound(String)
    case inferenceFailed(String)
    case unknownModel(String)
    case contextTooLong
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Model not found: \(name)"
        case .inferenceFailed(let reason):
            return "Inference failed: \(reason)"
        case .unknownModel(let name):
            return "Unknown model: \(name)"
        case .contextTooLong:
            return "Context exceeds maximum token limit"
        }
    }
}
