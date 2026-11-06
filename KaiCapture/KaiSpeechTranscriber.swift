//
//  KaiSpeechTranscriber.swift
//  Kai OS
//
//  Live speech-to-text from the microphone, using Apple's on-device recognizer only.
//  Audio never goes to a server: without an on-device model this fails instead.
//

import AVFoundation
import Foundation
import Speech

public enum KaiVoiceError: LocalizedError, Equatable, Sendable {
    case onDeviceUnavailable
    case noMicrophone

    public var errorDescription: String? {
        switch self {
        case .onDeviceUnavailable:
            return "On-device speech recognition isn't available for your language. Turn on Dictation in System Settings → Keyboard so macOS downloads it, then try again."
        case .noMicrophone:
            return "No microphone is available."
        }
    }
}

/// Abstracted so the notch's voice flow can be tested without a microphone or permission prompts.
@MainActor
public protocol KaiVoiceEngine: AnyObject {
    var isAuthorized: Bool { get }
    func requestAuthorization() async -> Bool
    func start(onPartial: @escaping @MainActor (String) -> Void) throws
    /// Stops listening and returns the final text.
    func finish() async -> String
    func cancel()
}

@MainActor
public final class KaiSpeechTranscriber: KaiVoiceEngine {
    private static let finishTimeout: Duration = .seconds(5)

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestText = ""
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var receivedFinal = false

    public init() {}

    public var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public func requestAuthorization() async -> Bool {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        return microphone && speech
    }

    public func start(onPartial: @escaping @MainActor (String) -> Void) throws {
        cancel()
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw KaiVoiceError.onDeviceUnavailable
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw KaiVoiceError.noMicrophone }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request
        latestText = ""
        receivedFinal = false

        Self.installTap(on: input, format: format, feeding: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.request = nil
            throw error
        }
        task = Self.recognize(with: recognizer, request: request) { [weak self] text, isFinal, failed in
            guard let self else { return }
            if let text {
                self.latestText = text
                onPartial(text)
            }
            if isFinal || failed {
                self.receivedFinal = true
                self.resumeFinish()
            }
        }
    }

    public func finish() async -> String {
        stopAudio()
        request?.endAudio()
        if !receivedFinal {
            // The recognizer normally answers quickly, and the timeout falls back to the last partial.
            let timeout = Task { [weak self] in
                try? await Task.sleep(for: Self.finishTimeout)
                guard !Task.isCancelled else { return }
                self?.resumeFinish()
            }
            await withCheckedContinuation { finishContinuation = $0 }
            timeout.cancel()
        }
        let text = latestText
        task?.cancel()
        task = nil
        request = nil
        return text
    }

    public func cancel() {
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        latestText = ""
        resumeFinish()
    }

    private func stopAudio() {
        guard engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    private func resumeFinish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    // These helpers are nonisolated because audio and recognition callbacks arrive on
    // background queues, and they must not inherit the main actor's isolation.

    private nonisolated static func installTap(on node: AVAudioInputNode, format: AVAudioFormat, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @MainActor (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in handler(text, isFinal, failed) }
        }
    }
}
