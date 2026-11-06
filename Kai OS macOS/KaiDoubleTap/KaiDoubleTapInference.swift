//
//  KaiDoubleTapInference.swift
//  Kai OS macOS
//
//  Local model fallback for DoubleTap — ollama / lmstudio
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Local model provider for DoubleTap inference
public enum DoubleTapModelProvider: String {
    case ollama = "Ollama"
    case lmstudio = "LM Studio"
    case llamaCpp = "llama.cpp"
    
    var defaultURL: String {
        switch self {
        case .ollama:
            return "http://localhost:11434"
        case .lmstudio:
            return "http://localhost:1234"
        case .llamaCpp:
            return "http://localhost:8080"
        }
    }
}

/// Configuration for local model inference
public struct DoubleTapModelConfig {
    public var provider: DoubleTapModelProvider
    public var model: String
    public var baseURL: String
    public var temperature: Double
    public var maxTokens: Int
    
    public init(
        provider: DoubleTapModelProvider = .ollama,
        model: String = "gemma:2b",
        baseURL: String? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 512
    ) {
        self.provider = provider
        self.model = model
        self.baseURL = baseURL ?? provider.defaultURL
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

/// DoubleTapInference — local model inference for smart reply generation
public final class KaiDoubleTapInference {
    
    public static let shared = KaiDoubleTapInference()
    
    /// The active model configuration
    public var config: DoubleTapModelConfig
    
    /// Whether a local model is currently reachable
    public var isLocalModelAvailable: Bool = false
    
    private init(config: DoubleTapModelConfig = DoubleTapModelConfig()) {
        self.config = config
        self.detectModelAvailability()
    }
    
    /// Detect if the configured local model is reachable
    public func detectModelAvailability() {
        isLocalModelAvailable = false
        
        // Check ollama first
        Task {
            let available = await self.checkModelAvailability(for: .ollama)
            if available {
                self.isLocalModelAvailable = true
                return
            }
            
            // Try lmstudio
            let available2 = await self.checkModelAvailability(for: .lmstudio)
            self.isLocalModelAvailable = available2
        }
    }
    
    /// Check if a specific model provider is reachable
    private func checkModelAvailability(for provider: DoubleTapModelProvider) async -> Bool {
        let url = URL(string: "\(provider.defaultURL)/api/tags")!
        
        return await withCheckedContinuation { continuation in
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["models"] as? [[String: Any]],
                      !models.isEmpty else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: true)
            }
            task.resume()
        }
    }
    
    /// Generate a reply using the local model
    /// - Parameters:
    ///   - prompt: The prompt to complete
    ///   - context: Optional conversation context
    ///   - writingStyle: Optional writing style reference
    /// - Returns: The generated reply text
    public func generateReply(
        prompt: String,
        context: String? = nil,
        writingStyle: String? = nil
    ) async throws -> String {
        guard isLocalModelAvailable else {
            throw DoubleTapInferenceError.localModelNotAvailable
        }
        
        let fullPrompt = buildPrompt(
            prompt: prompt,
            context: context,
            writingStyle: writingStyle
        )
        
        switch config.provider {
        case .ollama:
            return try await callOllama(prompt: fullPrompt)
        case .lmstudio:
            return try await callLMStudio(prompt: fullPrompt)
        case .llamaCpp:
            return try await callLlamaCpp(prompt: fullPrompt)
        }
    }
    
    /// Build the final prompt with context and style
    private func buildPrompt(
        prompt: String,
        context: String?,
        writingStyle: String?
    ) -> String {
        var parts: [String] = []
        
        if let style = writingStyle, !style.isEmpty {
            parts.append("Write in this style:\n\(style)")
            parts.append("")
        }
        
        if let context = context, !context.isEmpty {
            parts.append("Context:\n\(context)")
            parts.append("")
        }
        
        parts.append("Reply to: \(prompt)")
        return parts.joined(separator: "\n")
    }
    
    // MARK: - Ollama
    
    /// Call Ollama API for completion
    private func callOllama(prompt: String) async throws -> String {
        let url = URL(string: "\(config.baseURL)/api/generate")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": config.model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": config.temperature,
                "num_predict": config.maxTokens
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DoubleTapInferenceError.apiError("Ollama", (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responseText = json?["response"] as? String,
              !responseText.isEmpty else {
            throw DoubleTapInferenceError.emptyResponse("Ollama")
        }
        
        return responseText
    }
    
    // MARK: - LM Studio
    
    /// Call LM Studio API (OpenAI-compatible)
    private func callLMStudio(prompt: String) async throws -> String {
        let url = URL(string: "\(config.baseURL)/v1/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": config.maxTokens,
            "temperature": config.temperature
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DoubleTapInferenceError.apiError("LM Studio", (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]] ?? []
        func extractText(from obj: Any?) -> String? {
            guard let dict = obj as? [String: Any] else { return nil }
            return dict["content"] as? String
        }
        let content = extractText(from: choices.first?["message"])

        
        guard let output = content, !output.isEmpty else {
            throw DoubleTapInferenceError.emptyResponse("LM Studio")
        }
        
        return output
    }
    
    // MARK: - llama.cpp
    
    /// Call llama.cpp server
    private func callLlamaCpp(prompt: String) async throws -> String {
        let url = URL(string: "\(config.baseURL)/completion")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "prompt": prompt,
            "n_predict": config.maxTokens,
            "temp": config.temperature,
            "stream": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DoubleTapInferenceError.apiError("llama.cpp", (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? String,
              !content.isEmpty else {
            throw DoubleTapInferenceError.emptyResponse("llama.cpp")
        }
        
        return content
    }
}

/// Errors for DoubleTap inference
public enum DoubleTapInferenceError: Error, LocalizedError {
    case localModelNotAvailable
    case apiError(String, Int)
    case emptyResponse(String)
    case invalidConfig
    
    public var errorDescription: String? {
        switch self {
        case .localModelNotAvailable:
            return "No local model available — install Ollama or LM Studio"
        case .apiError(let provider, let code):
            return "\(provider) API error: \(code)"
        case .emptyResponse(let provider):
            return "\(provider) returned empty response"
        case .invalidConfig:
            return "Invalid model configuration"
        }
    }
}
