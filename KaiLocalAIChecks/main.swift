// Plain-executable checks for KaiLocalAI: Command Line Tools ship neither XCTest
// nor the Swift Testing macros, so `swift test` is unavailable without Xcode.
// Run with: swift run KaiLocalAIChecks
import Foundation
@testable import KaiLocalAI
import CoreGraphics
import KaiNotchCore

var failures = 0

func check(_ name: String, _ body: () throws -> Bool) {
    do {
        let passed = try body()
        print("\(passed ? "PASS" : "FAIL")  \(name)")
        if !passed { failures += 1 }
    } catch {
        print("FAIL  \(name): threw \(error)")
        failures += 1
    }
}

check("parses a content chunk") {
    let line = #"{"model":"m","message":{"role":"assistant","content":"Hi"},"done":false}"#
    return try KaiOllamaClient.parseStreamLine(line) == KaiOllamaChunk(content: "Hi", done: false)
}

check("parses the final chunk") {
    let line = #"{"model":"m","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop"}"#
    return try KaiOllamaClient.parseStreamLine(line) == KaiOllamaChunk(content: "", done: true)
}

check("a server error line throws the server's message") {
    do {
        _ = try KaiOllamaClient.parseStreamLine(#"{"error":"model not found"}"#)
        return false
    } catch let error as KaiOllamaError {
        return error == .server("model not found")
    }
}

check("a blank line is ignored") {
    try KaiOllamaClient.parseStreamLine("   ") == nil
}

check("the model list keeps only chat-capable models") {
    let body = #"""
    {"models":[
      {"name":"qwen3.6-coding:latest","capabilities":["completion","tools"]},
      {"name":"nomic-embed-text:latest","capabilities":["embedding"]},
      {"name":"older-ollama-model:latest"}
    ]}
    """#
    return try KaiOllamaClient.parseChatModels(Data(body.utf8))
        == ["qwen3.6-coding:latest", "older-ollama-model:latest"]
}

check("the chat request streams and disables thinking") {
    let client = KaiOllamaClient(baseURL: URL(string: "http://localhost:11434")!)
    let request = try client.chatRequest(
        model: "m",
        messages: [KaiOllamaMessage(role: "user", content: "hello")]
    )
    guard request.url?.absoluteString == "http://localhost:11434/api/chat",
          request.httpMethod == "POST",
          let body = request.httpBody,
          let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
          let messages = json["messages"] as? [[String: String]]
    else { return false }
    return json["model"] as? String == "m"
        && json["stream"] as? Bool == true
        && json["think"] as? Bool == false
        && messages == [["role": "user", "content": "hello"]]
}

// MARK: Notch geometry

// A 14-inch MacBook Pro in its default scaled mode.
let macBook = KaiNotchLayout(
    screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    safeAreaTop: 38, leftAreaWidth: 668, rightAreaWidth: 668, menuBarHeight: 38
)

check("the closed frame matches the hardware notch") {
    macBook.hasHardwareNotch && macBook.frame(for: .closed) == CGRect(x: 668, y: 944, width: 176, height: 38)
}

check("a notch on a half point snaps to whole points and stays centered") {
    let halfPoint = KaiNotchLayout(
        screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTop: 32, leftAreaWidth: 771.5, rightAreaWidth: 771.5, menuBarHeight: 32
    )
    return halfPoint.frame(for: .closed) == CGRect(x: 771, y: 1085, width: 186, height: 32)
        && halfPoint.frame(for: .closed).midX == 864
}

check("the peek frame adds wings and stays flush with the top") {
    let peek = macBook.frame(for: .peek)
    return peek.midX == 756 && peek.width > 176 && peek.maxY == 982 && peek.height == 38
}

check("the expanded frame hangs centered from the top of the screen") {
    let expanded = macBook.frame(for: .expanded)
    return expanded.midX == 756 && expanded.maxY == 982 && expanded.height > 200
}

check("a screen without a notch gets a centered pill") {
    let external = KaiNotchLayout(
        screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil, menuBarHeight: 24
    )
    let closed = external.frame(for: .closed)
    return !external.hasHardwareNotch && closed.midX == 960 && closed.maxY == 1080 && closed.height == 24
}

check("a display arranged at an offset keeps its own coordinates") {
    let offset = KaiNotchLayout(
        screenFrame: CGRect(x: -1920, y: 200, width: 1920, height: 1080),
        safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil, menuBarHeight: 24
    )
    let closed = offset.frame(for: .closed)
    return closed.midX == -960 && closed.maxY == 1280
}

check("the expanded frame never leaves a narrow screen") {
    let narrow = KaiNotchLayout(
        screenFrame: CGRect(x: 0, y: 0, width: 400, height: 300),
        safeAreaTop: 0, leftAreaWidth: nil, rightAreaWidth: nil, menuBarHeight: 24
    )
    let screen = CGRect(x: 0, y: 0, width: 400, height: 300)
    return screen.contains(narrow.frame(for: .expanded))
}

// MARK: Right Command gesture

check("a quick press and release is a tap") {
    var gesture = KaiModifierGesture()
    gesture.press(at: 10)
    return gesture.release(at: 10.1)
}

check("a long hold is not a tap") {
    var gesture = KaiModifierGesture()
    gesture.press(at: 10)
    return !gesture.release(at: 10.6)
}

check("a key chord such as Command-C is not a tap") {
    var gesture = KaiModifierGesture()
    gesture.press(at: 10)
    gesture.interrupt()
    return !gesture.release(at: 10.1)
}

check("a release with no press is not a tap") {
    var gesture = KaiModifierGesture()
    return !gesture.release(at: 10)
}

// Nothing listens on port 9, so this exercises the "Ollama is not running" path.
let closedPort = KaiOllamaClient(baseURL: URL(string: "http://127.0.0.1:9")!)
do {
    _ = try await closedPort.listChatModels()
    print("FAIL  a stopped server reports unreachable: request succeeded")
    failures += 1
} catch let error as KaiOllamaError where error == .unreachable("http://127.0.0.1:9") {
    print("PASS  a stopped server reports unreachable")
} catch {
    print("FAIL  a stopped server reports unreachable: threw \(error)")
    failures += 1
}

do {
    for try await _ in closedPort.streamChat(model: "m", messages: []) {}
    print("FAIL  a stopped server fails the chat stream: stream finished")
    failures += 1
} catch let error as KaiOllamaError where error == .unreachable("http://127.0.0.1:9") {
    print("PASS  a stopped server fails the chat stream")
} catch {
    print("FAIL  a stopped server fails the chat stream: threw \(error)")
    failures += 1
}

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
