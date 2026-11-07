//
//  KaiFallback.swift
//  Kai OS macOS
//
//  Cloud-to-local fallback chain
//  ChatGPT → Claude → Custom → Gemma (local)
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation

// MARK: - Default Models

/// Default model names for cloud endpoints. Override these to switch models.
public enum KaiFallbackModels {
    public static var chatGPT: String = "gpt-4o"
    public static var claude: String = "claude-sonnet-4-20250514"
}

/// Fallback chain order
public enum FallbackOrder: String {
    case chatgpt = "chatgpt"
    case claude = "claude"
    case custom = "custom"
    case gemmaLocal = "gemmaLocal"
}

/// KaiFallbackManager — manages the fallback chain between cloud and local AI
public final class KaiFallbackManager {
    
    public static let shared = KaiFallbackManager()
    
    /// Current primary model provider
    public var currentProvider: FallbackOrder = .chatgpt
    
    /// Chain of fallback providers in priority order
    public var fallbackChain: [FallbackOrder] = [.chatgpt, .claude, .custom, .gemmaLocal]
    
    /// API keys (loaded from secure store)
    private var openAIAPIKey: String?
    private var anthropicAPIKey: String?
    private var customEndpointURL: String?
    private var customAPIKey: String?
    
    private init() {
        loadAPIKeys()
    }
    
    /// Load API keys from secure credential store
    private func loadAPIKeys() {
        let store = SecureStore.shared
        self.openAIAPIKey = store.read(key: "kai.openai.api_key")
        self.anthropicAPIKey = store.read(key: "kai.anthropic.api_key")
        self.customEndpointURL = store.read(key: "kai.custom.endpoint")
        self.customAPIKey = store.read(key: "kai.custom.api_key")
    }
    
    /// Run the inference with the fallback chain
    /// - Parameters:
    ///   - prompt: The user prompt
    ///   - context: Optional context for the inference
    /// - Returns: Inference result
    public func runWithFallback(prompt: String, context: String? = nil) async throws -> String {
        let fullPrompt = context.map { "\($0)\n\n\(prompt)" } ?? prompt
        
        for provider in fallbackChain {
            do {
                switch provider {
                case .chatgpt:
                    return try await callChatGPT(prompt: fullPrompt)
                case .claude:
                    return try await callClaude(prompt: fullPrompt)
                case .custom:
                    return try await callCustom(prompt: fullPrompt)
                case .gemmaLocal:
                    return try await callLocalGemma(prompt: fullPrompt)
                }
            } catch let error as KaiFallbackError {
                // Log and continue to next fallback
                print("[KaiFallback] Provider \(provider.rawValue) failed: \(error.localizedDescription)")
                continue
            } catch {
                continue
            }
        }
        
        throw KaiFallbackError.allProvidersFailed
    }
    
    /// Call ChatGPT via OpenAI Chat Completions API
    private func callChatGPT(prompt: String) async throws -> String {
        guard let apiKey = openAIAPIKey else {
            throw KaiFallbackError.noAPIKey(provider: "chatgpt")
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": KaiFallbackModels.chatGPT,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 4096,
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw KaiFallbackError.apiError(provider: "chatgpt", code: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]] ?? []
        let content = choices.compactMap { $0["message"] as? [String: Any] }?
            .compactMap { $0["content"] as? String }.joined(separator: "\n")
        
        guard let text = content, !text.isEmpty else {
            throw KaiFallbackError.emptyResponse(provider: "chatgpt")
        }
        
        return text
    }
    
    /// Call Claude via Anthropic Messages API
    private func callClaude(prompt: String) async throws -> String {
        guard let apiKey = anthropicAPIKey else {
            throw KaiFallbackError.noAPIKey(provider: "claude")
        }
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("api-key \(apiKey)", forHTTPHeaderField: "x-api-key")
        request.setValue("2024-10-22", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": KaiFallbackModels.claude,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw KaiFallbackError.apiError(provider: "claude", code: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let contentBlocks = json?["content"] as? [[String: Any]]
        let textBlocks = contentBlocks?.compactMap { $0["text"] as? String }
        let result = textBlocks?.joined(separator: "\n")
        
        guard let output = result, !output.isEmpty else {
            throw KaiFallbackError.emptyResponse(provider: "claude")
        }
        
        return output
    }
    
    /// Call a custom endpoint (user-configurable)
    private func callCustom(prompt: String) async throws -> String {
        guard let endpoint = customEndpointURL,
              let url = URL(string: endpoint),
              let apiKey = customAPIKey else {
            throw KaiFallbackError.noAPIKey(provider: "custom")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "prompt": prompt,
            "max_tokens": 4096
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw KaiFallbackError.apiError(provider: "custom", code: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = json?["response"] as? String ?? json?["text"] as? String
        
        guard let output = result, !output.isEmpty else {
            throw KaiFallbackError.emptyResponse(provider: "custom")
        }
        
        return output
    }
    
    /// Call local Gemma model on-device
    private func callLocalGemma(prompt: String) async throws -> String {
        // Uses the local inference engine
        return try await KaiEngine.shared.infer(prompt)
    }
    
    /// Set the primary (top) provider in the chain
    public func setPrimaryProvider(_ provider: FallbackOrder) {
        guard let index = fallbackChain.firstIndex(of: provider) else { return }
        fallbackChain.remove(at: index)
        fallbackChain.insert(provider, at: 0)
        currentProvider = provider
    }
    
    /// Remove a provider from the chain
    public func removeProvider(_ provider: FallbackOrder) {
        guard fallbackChain.contains(provider) else { return }
        fallbackChain.removeAll { $0 == provider }
        if currentProvider == provider {
            currentProvider = fallbackChain.first ?? .gemmaLocal
        }
    }
}

/// Errors specific to the fallback manager
public enum KaiFallbackError: Error, LocalizedError {
    case noAPIKey(provider: String)
    case apiError(provider: String, code: Int)
    case emptyResponse(provider: String)
    case allProvidersFailed
    
    public var errorDescription: String? {
        switch self {
        case .noAPIKey(let provider):
            return "No API key configured for \(provider)"
        case .apiError(let provider, let code):
            return "\(provider) API error: HTTP \(code)"
        case .emptyResponse(let provider):
            return "\(provider) returned empty response"
        case .allProvidersFailed:
            return "All fallback providers failed"
        }
    }
}

/// Secure store for API keys (backed by macOS Keychain)
public final class SecureStore {
    public static let shared = SecureStore()
    
    private init() {}
    
    /// Read a value from Keychain
    public func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.kai",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    /// Write a value to Keychain
    public func write(key: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.kai",
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8)
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    /// Delete a value from Keychain
    public func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.kai",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
