//
//  main.swift
//  kai-hook
//
//  The command that Claude Code hooks run. It reads the hook payload from stdin and passes it to the
//  running Kai OS app over a local socket. For a permission request it prints Kai's decision once you
//  press Allow or Deny. It never allows anything itself: in every other case (Kai not running, no answer
//  in time, a bad reply) it prints nothing and exits 0, so Claude Code asks in the terminal as usual.
//

import Foundation
import KaiDesk

let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty, let event = KaiHookEvent.parse(input) else { exit(0) }

let path = KaiHookSocket.defaultPath
let wantsAnswer = event.name == .permissionRequest
let reply = KaiHookClient.send(input, socketPath: path, waitForReply: wantsAnswer, timeout: 58)

if wantsAnswer, let reply, !reply.isEmpty,
   (try? JSONSerialization.jsonObject(with: reply)) is [String: Any] {
    FileHandle.standardOutput.write(reply)
}
exit(0)
