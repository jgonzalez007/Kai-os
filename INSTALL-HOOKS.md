# Claude Code hooks for Kai OS

Kai OS can show Claude Code's permission requests in the notch, so you can allow or deny them there. It also shows a "Done" peek when a task ends, and the helper agents that are running.

**Kai OS never edits your Claude Code settings.** You add the hooks by hand, you can check them, and you can remove them any time.

The idea (approve from the notch, a Done peek, helper agents) comes from [Glance for Mac](https://github.com/glanceformac/glance). This is Kai OS's own code: a small helper plus a private socket, no copied source.

## Set it up

1. Install Kai OS with `scripts/install-app.sh`. It puts the `kai-hook` helper inside the app, next to the main program.
2. Open Kai OS, then Settings, then **Desk**. Turn on **Listen for Claude Code**.
3. Click **Copy hook setup**. The text has the right path for your copy of the app.
4. Back up your settings: `cp ~/.claude/settings.json ~/.claude/settings.json.before-kai` (if the file does not exist, create it with `{}` in it).
5. Open `~/.claude/settings.json`.
   - No `"hooks"` key yet: paste the copied block in as a new top-level key. Mind the comma after the previous key.
   - Already has `"hooks"`: for each event in the copied block, add Kai's entry to that event's list next to yours, or add the event if it is missing. Do not add a second `"hooks"` key, and do not change your own entries.
6. Check the file is still valid JSON: `python3 -m json.tool ~/.claude/settings.json > /dev/null && echo OK`
7. Restart any running Claude Code sessions so they load the hooks.

The block looks like this (the path is the helper inside your app, quoted because "Kai OS.app" has a space):

```json
{
  "hooks": {
    "PermissionRequest": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "'/Users/you/Applications/Kai OS.app/Contents/MacOS/kai-hook'", "timeout": 75 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "'/Users/you/Applications/Kai OS.app/Contents/MacOS/kai-hook'", "timeout": 10 } ] }
    ]
  }
}
```

The copied block also has `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `StopFailure` and `SessionEnd`, with `timeout` 10.

## What each hook does

| Event | What Kai OS shows |
|---|---|
| `PermissionRequest` | "Claude needs your OK": the command or file path, the project folder, Allow and Deny. With Accessibility permission you can also press ⌃⌥Y or ⌃⌥N. |
| `Stop`, `StopFailure` | A "Claude done" (or "Claude failed") peek in the notch, and a line in the Claude Code tab with the project and how long the turn took. |
| `UserPromptSubmit` | Nothing visible. It records when the turn started, so Done can show the duration. |
| `SubagentStart`, `SubagentStop` | One row per running helper agent in the Claude Code tab ("Explore", "Plan" or "Helper"), and a count in the notch. A row says "needs your OK" while that helper waits for you. |
| `SessionEnd` | Nothing visible. It clears that session's helpers. |

Only these fields are read: the event, the session, the project folder, the tool name, the helper agent id and type, and for a permission request a short summary (the command, the file path, a URL, or up to 300 characters of each short text field). File contents and tool output are never read. A very long command is cut at 2,000 characters on the card.

## Safety

- It never allows anything on its own. An allow decision is sent only after you press **Allow** (or ⌃⌥Y) in Kai OS.
- Allow returns `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` with no changed input and no new permission rules. Your own deny and ask rules in Claude Code still apply.
- Deny returns a deny decision with the message "Denied by the user from Kai OS."
- In each of these cases the helper prints nothing and exits 0, so Claude Code asks in the terminal as usual:
  - Kai OS is not running, or Listen for Claude Code is off
  - the socket is not a real socket owned by you (a symlink or plain file is refused)
  - you do not answer within 56 seconds (Kai OS gives up) or 58 seconds (the helper gives up)
  - Kai OS quits while the card is showing, or the reply is malformed
- The only channel is a Unix socket at `~/Library/Application Support/Kai OS/kai.sock` (folder mode 0700, socket mode 0600). Kai OS also checks that the connecting process belongs to your user. No network port is opened.
- The hook `timeout` of 75 seconds is longer than the helper's own 58 second limit, so Claude Code never has to kill it.

## Check it works

With Kai OS running and **Listen for Claude Code** on, paste this in a terminal. The card should appear in the notch. Press Allow or Deny, and the decision prints in the terminal.

```sh
H="$HOME/Applications/Kai OS.app/Contents/MacOS/kai-hook"
echo '{"hook_event_name":"PermissionRequest","cwd":"'"$PWD"'","tool_name":"Bash","tool_input":{"command":"echo hello"}}' | "$H"
```

Then in Claude Code, ask for something that needs permission. The same card appears.

## Remove it

Delete every entry whose `"command"` ends in `kai-hook` from `~/.claude/settings.json`, and any event list that is left empty. Or put your backup back: `cp ~/.claude/settings.json.before-kai ~/.claude/settings.json`. Restart Claude Code sessions. If Kai OS is not running, the hooks do nothing and Claude Code asks in the terminal.

## Testing without touching your real setup

`KAI_SOCKET_PATH` points both the app and the helper at another socket, so a test copy never uses the real one.
