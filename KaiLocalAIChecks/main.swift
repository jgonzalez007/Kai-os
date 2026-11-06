// Plain-executable checks for KaiLocalAI: Command Line Tools ship neither XCTest
// nor the Swift Testing macros, so `swift test` is unavailable without Xcode.
// Run with: swift run KaiLocalAIChecks
import Foundation
@testable import KaiLocalAI
import CoreGraphics
@testable import KaiLocalData
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

// MARK: Assistant tools

check("a streamed tool call is parsed with its arguments") {
    let line = #"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"search_files","arguments":{"query":"tax","limit":3}}}]},"done":false}"#
    guard let call = try KaiOllamaClient.parseStreamLine(line)?.toolCalls.first else { return false }
    return call.name == "search_files"
        && call.arguments["query"]?.stringValue == "tax"
        && call.arguments["limit"]?.intValue == 3
}

check("the chat request includes tool definitions when given") {
    let client = KaiOllamaClient(baseURL: URL(string: "http://localhost:11434")!)
    let tool = KaiOllamaTool(
        name: "search_files",
        description: "Search files",
        parameters: [KaiOllamaTool.Parameter(name: "query", type: "string", description: "Words to find", required: true)]
    )
    let request = try client.chatRequest(model: "m", messages: [], tools: [tool])
    let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
    let function = (json?["tools"] as? [[String: Any]])?.first?["function"] as? [String: Any]
    let parameters = function?["parameters"] as? [String: Any]
    return function?["name"] as? String == "search_files"
        && parameters?["required"] as? [String] == ["query"]
        && (parameters?["properties"] as? [String: Any])?["query"] != nil
}

check("a tool result message carries the tool name") {
    let data = try JSONEncoder().encode(KaiOllamaMessage(role: "tool", content: "ok", toolName: "search_files"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return json?["tool_name"] as? String == "search_files" && json?["tool_calls"] == nil
}

// MARK: Local data parsing

check("AppleScript records split on the separator characters") {
    let output = "a\u{1F}b\u{1E}c\u{1F}d\u{1E}\n"
    return KaiAppleScriptRecords.parse(output) == [["a", "b"], ["c", "d"]]
}

check("an ISO date from AppleScript is read as local time") {
    guard let date = KaiAppleScriptRecords.date(fromISO: "2026-11-06T15:30:00") else { return false }
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    return parts.year == 2026 && parts.month == 11 && parts.day == 6 && parts.hour == 15 && parts.minute == 30
}

check("a mail record becomes a mail item") {
    let items = KaiMailSource.items(from: [["42", "Ana <ana@example.com>", "Hello", "2026-11-06T09:00:00", "false", "true"]])
    return items.count == 1 && items[0].id == "42" && items[0].sender == "Ana <ana@example.com>"
        && items[0].subject == "Hello" && !items[0].isRead && items[0].isFlagged
}

check("a malformed mail record is skipped") {
    KaiMailSource.items(from: [["only", "two"]]).isEmpty
}

check("a note record becomes a note item") {
    let items = KaiNotesSource.items(from: [["n1", "Groceries", "Milk", "2026-11-06T09:00:00"]])
    return items.count == 1 && items[0].title == "Groceries" && items[0].body == "Milk"
}

check("an automation refusal is reported as not authorized") {
    let error = KaiSourceError.fromAppleScriptFailure(app: "Mail", message: "execution error: Not authorized to send Apple events to Mail. (-1743)")
    return error == .notAuthorized("Mail")
}

check("Spotlight queries cannot be read as command-line flags") {
    KaiSpotlightSource.sanitizedQuery("  --help me ") == "help me" && KaiSpotlightSource.sanitizedQuery(" - ") == nil
}

check("Spotlight results skip Library folders and hidden paths") {
    let home = "/Users/me"
    let kept = KaiSpotlightSource.isUserFacing(path: "/Users/me/Documents/tax.pdf", home: home)
    let library = KaiSpotlightSource.isUserFacing(path: "/Users/me/Library/Caches/tax.pdf", home: home)
    let hidden = KaiSpotlightSource.isUserFacing(path: "/Users/me/.cache/tax.pdf", home: home)
    return kept && !library && !hidden
}

// MARK: Scripts and Spotlight on this Mac

func compiles(_ script: String) -> Bool {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".scpt")
    defer { try? FileManager.default.removeItem(at: output) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
    process.arguments = ["-o", output.path, "-e", script]
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

check("the Mail script compiles against Mail's dictionary") { compiles(KaiMailSource.script(limit: 5)) }
check("the Notes script compiles against Notes' dictionary") { compiles(KaiNotesSource.script(limit: 5, bodyLimit: 100)) }

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
