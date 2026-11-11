# Try Kai on your Mac

Unit tests pass for everything below, but none of it has been tried on a real screen yet. Go in order. Each item says what to do, what you should see, and what to tell me if it doesn't match. Tick the box when it works.

Use a throwaway document, a test Slack channel (or a DM to yourself) and a mailbox where nothing important can be lost.

## 0. Before you start

- [ ] Kai OS is running from `~/Applications/Kai OS.app` (menu bar icon is there).
- [ ] Settings → Permissions: Accessibility and Screen Recording show as allowed. Press **Test** on each row (see 6).

## 1. Permission Test buttons

- [ ] Settings → Permissions → **Test** on Accessibility: says it read the front app. 
- [ ] **Test** on Screen Recording: says a small picture was taken.
- [ ] **Test** on Calendar: gives a count of events in the next 7 days.
- [ ] **Test** on Mail and Notes (open them first): each answers one harmless question.
- If one fails: send me the exact message shown.

## 2. Proofread and Rewrite

1. In TextEdit (or Notes) type: `i has a apple and teh dog barked loud`. Select it.
- [ ] Press Proofread (your usual way). A suggestion appears with **Review 3 changes** (or similar).
- [ ] Open the review, untick one change. The button reads "Replace with 2 of 3 changes".
- [ ] Press it. Only the ticked changes are in the text. Nothing else changed.
2. Same test in **Slack** (type in a message box, select, don't send) and in **Chrome** (a text box on any site).
- [ ] The text is replaced in both. If not, tell me the app name.
3. Select a sentence → notch → **Rewrite ▾** → Make it concise.
- [ ] Kai shows its version first. Your text changes only after you approve.
4. Settings → AI & Web → How Kai answers → Rewrite prompts: add your own prompt.
- [ ] It appears in the Rewrite menu.

## 3. Today chip

- [ ] Hover the notch: a **Today** chip is there.
- [ ] Press it: urgent items first, each with a **Dismiss** button.
- [ ] **Open For You to act on these** opens the For You page. Nothing was sent from the notch card.

## 4. Mail cleanup and undo

Use a test mailbox.
- [ ] Mail page → Clean up: Kai shows what it will do and waits for your click.
- [ ] After you approve, Settings → Activity lists it with an **Undo** button.
- [ ] Press Undo: the mail is marked unread again / the Kai rule is gone (check in Mail → Settings → Rules; only rules starting "Kai:" are ever touched).
- [ ] Kai never sent or permanently deleted anything.

## 5. Calendar: Find a time

- [ ] Calendar page → **Find a time** → pick a length: you get free slots that don't overlap your events.
- [ ] Pick one: Kai shows an approval card before anything is added.
- [ ] Overlapping events show a conflict badge.

## 6. Settings → Activity page

- [ ] Every approved action from the steps above is listed, newest first, with Done / Problem / Declined.
- [ ] Filters (Problems, Mail, Writing, Calendar) change the list.
- [ ] A Slack write is described as "Written at your cursor in Slack", not as email.

## 7. Knowledge

- [ ] Knowledge page → add a folder you own. The progress counter moves and finishes.
- [ ] Drop a PDF and an Excel file into the page: both are listed afterwards.
- [ ] Ask Kai a question only a file can answer: the answer names the file.
- [ ] Ask something Kai can't know: it says so, and the question shows under "What Kai couldn't find".
- [ ] Optional: turn on Search by meaning (downloads about 274 MB). Ask using different words than the file uses.

## 8. Sidekick on a local model

Start in **Ask for each action** mode with a harmless task: "Open TextEdit and type hello".
- [ ] You see numbered boxes drawn on the screenshot.
- [ ] Each action waits for Approve. Esc stops it.
- [ ] Ask "open Chrome" while Chrome is already open: it opens a **new tab** instead of reusing the current one.
- [ ] After a task with a problem, Settings → Sidekick → Lessons shows a tip you can delete or turn off.

## 9. Sidekick: new safety rules (Run on its own)

Switch to **Run on its own**, then use a throwaway Slack DM to yourself and a TextEdit window.
- [ ] Task: "Type hello in TextEdit." Runs without asking.
- [ ] Task: "In Slack, write hi in the box and send it." Kai **asks** before the Send click and before Return.
- [ ] Task: "Open https://example.com/?q=test". Kai **asks**, because the address has a query. "Open https://example.com" does not ask.
- [ ] Task: "Open Terminal", "open Shortcuts", "open Xcode": all refused.
- [ ] Task: "Press control+option+y": asks first.

## 10. Sidekick on Claude (uses your Claude subscription)

- [ ] Settings → Sidekick → Model: pick Claude Sonnet (cloud). The card shows where Claude Code was found.
- [ ] Without turning on **I understand**, start a task: Kai refuses and says why.
- [ ] Turn it on and run "Open Calendar". It works; each step takes a few seconds.
- [ ] Put 1Password or System Settings in front and start a task: Kai refuses to send the screen.
- [ ] Your plan usage in claude.ai went up a little (screenshots count).

## What to send me when something fails

The step number, the app you were in, and the exact message shown. For Sidekick, also the last lines of the Sidekick event log.
