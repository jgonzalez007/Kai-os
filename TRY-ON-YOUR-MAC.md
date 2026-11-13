# Try Kai on your Mac

Unit tests pass for everything below, but none of it has been tried on a real screen yet. Go in order. Each item says what to do, what you should see, and what to tell me if it doesn't match. Tick the box when it works.

Use a throwaway document, a test Slack channel (or a DM to yourself) and a mailbox where nothing important can be lost.

**Done so far:** 1 (permission tests), 2 (Rewrite in Slack, find and replace), 3 (Today). **Still to do:** 2 in Chrome and the review of changes, 4 to 10, and the new sections 11 to 14 at the end.

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

## 11. Cobalt Plasma look (new default)

- [ ] Settings → Appearance → **Look**: switch to Classic, then back to Cobalt Plasma. The window redraws and you stay on the same page.
- [ ] Cobalt: cards are deep blue with a glowing cyan edge, toggles are neon switches, sliders glow, main buttons have a cyan edge.
- [ ] Open the notch: the slim bar has room around the input, and the chips do not touch. If the bar is tight, the shortcut icons fold into a **⋯** menu.
- [ ] Open **Today** and a reply card: both have the plasma edge and are readable.
- Tell me anything that is hard to read or looks off, with the screen it was on.

## 12. Replies that use context

- [ ] In Mail, select an email that asks for a time (for example "can you do Tuesday at 2?"). Double tap your shortcut key.
- [ ] The panel says what it used ("Written using your calendar, …"), and the reply agrees with your real calendar.
- [ ] Press **No, politely**, then **Yes**: the draft changes each time.
- [ ] A draft with a `[decision]` in brackets waits for you and shows "This reply needs your decision".
- [ ] In a Slack DM, the same: the panel names what it used.

## 13. Sidekick: new behaviour

Use "Ask me before every action" first.
- [ ] Task: "Open Safari and go to apple.com". Safari ends up in front with a window. The Sidekick panel is at the **bottom left**, not over the address bar.
- [ ] Task: "Open Chrome and look for airbnb houses near Austin for Nov 22 to 24". It does not loop on "Open Chrome".
- [ ] A task with a real choice ("find me a restaurant in Austin"): it may ask you a question with two answers. Pick one: it carries on with it.
- [ ] When it finishes, the message says what it saw. A task it can't do ends with "Couldn't finish: …".
- [ ] "What's in my unread mail?" uses the mail tool, not clicking around Mail.
- [ ] Switch the model to Claude: the same mail question is refused with "doesn't read your mail to a model in the cloud".

## 14. Sidekick recipes

- [ ] After a task that worked, a card says "That worked. Keep it to run again". Name it and press **Save recipe**.
- [ ] The recipe shows under **Recipes** with its step count.
- [ ] Press **Use**: the task loads, with the recipe's steps guiding the run. Edit the wording to add a `{blank}`, such as `{person}`, press **Keep this wording**, and a box for it appears.
- [ ] Run it again with a different value in the blank. It follows the same path faster.
- [ ] Saved steps never contain what you typed, or a web address's search part.

## 15. Chat on Claude: research and one conversation

You need Claude Code installed and signed in (Settings → Sidekick shows where it was found).
- [ ] Settings → Sidekick → **Claude chat research**: turn on "I understand", then turn on **Mail** only.
- [ ] Open a chat, pick **Claude Sonnet (research)** in the model menu (it shows once the chat has a message).
- [ ] Ask: "Who emailed me about <a real topic in your inbox>, and what do they want?" The status line shows Kai searching and reading mail. The answer names the sender and quotes what the message asks for.
- [ ] Turn Mail off and ask again: Claude says Mail is switched off in Settings and does not read it.
- [ ] Ask "What's on my calendar this week?" with Calendar off: same refusal. Turn it on: it answers.
- [ ] Ask "Open Notes and make a note called Test". A card appears in the chat: **Do this on your screen**, with **Start** and **Not now**. Nothing happens until you press Start.
- [ ] Press **Not now**: the card says "Not started" and Claude tells you nothing was done.
- [ ] Ask again, press **Start**: Sidekick does it (asking before each step in "Ask me before every action" mode) and the card shows the result when it finishes.
- [ ] On the Sidekick page run any task: its task and result appear in the chat as well.
- [ ] Quit and reopen Kai OS: the conversation is still there. **New chat** clears it.
- If it fails: send the step, the message shown, and whether Mail access (Settings → Mailbox access) allows reading whole mailboxes.

## 16. Memory, long chats and screen tasks from any chat model

- [ ] Settings → Sidekick → **What Kai remembers**: add "I prefer short answers in bullet points". Open a chat and ask something: the answer is in bullets.
- [ ] Try adding a note with a password or a web address: it is refused with a reason.
- [ ] In a chat say "remember that my manager is Maria". The note appears in the list marked "Added from a chat". Turn it off: a new chat no longer uses it. Delete it.
- [ ] Ask "what did we say earlier about the budget?" in a long chat: Kai searches this chat's history and quotes it.
- [ ] Keep one chat going past about 40 messages (or lots of long answers) on a local model, then ask about something from the start: it still knows the gist. (The summary is written on this Mac by the local model; with only Claude available, older messages are just cut.)
- [ ] With a **local** chat model, say "open Notes and make a note called Test": the same Start / Not now card appears, and Start runs it.
- [ ] After a screen task started from chat, ask "what did you just do?": the answer lists the steps.

## 17. Linked notes (Knowledge → Linked notes)

Needs Ollama running with a local model (gemma4:e4b works). First index your sources on the Knowledge setup page.
- [ ] Knowledge → **Linked notes**: the status line shows how many items are waiting. Press **Read new items**. The line counts through "Reading 12 of 150…". It takes a few seconds per item, so start with a few dozen.
- [ ] When it finishes, the line says how many were kept and how many skipped. Newsletters, receipts and anything private (medical, account numbers) should be in the skipped count.
- [ ] Press **Write notes**. A folder `~/Kai OS - Linked Notes` appears with People, Projects, Commitments, Topics and an Overview.
- [ ] The constellation shows a dot per note and a thread per link. Click a dot: the note opens. Click a blue link inside it: you go to that note. The arrow goes back.
- [ ] Press **Edit** on a note, change a line, **Save**. Then press **Update notes** again: your edited note is not rewritten (the status line says "kept as you edited them").
- [ ] **New note** makes a note of your own in Topics. **Trash** moves one to the Trash.
- [ ] Open the folder in Obsidian or any editor: they are plain Markdown files.
- [ ] In chat: ask "who is <a person in your notes> and what are they working on?" The answer uses the linked notes (and says so), then you can ask it to open the full note.
- [ ] With Claude as the chat model and **Knowledge base** switched on under Claude chat research, the same question works; with it off, Claude is told knowledge is switched off.
- [ ] Night Shift (if enabled) now also reads new items and updates the notes before the portrait. "About you" is written from the summaries once there are 20 or more.
- If something fails: the step number and the message on the status line.

## 18. Smarter replies (email and Slack)

1. Settings → Double Tap → Writing style: press Learn again. Kai now keeps up to 8 of your own sent messages as voice examples (Clear removes them).
2. Build the Linked notes first (Knowledge → Linked notes → Build), so replies can use the notes about the person and project.
3. Open an email from someone you have history with, double tap. The line under the draft lists what was used (profile, files, earlier messages, voice examples). The draft should name the real project or earlier promise, not be generic.
4. Settings → Sidekick → Claude chat research: turn on "I understand", then "Write email and Slack replies with Claude". Draft again: the line ends with "written by Claude", and the draft should be clearly more specific. Screenshots never go to Claude.
5. Turn Claude off (or sign out of Claude Code): the local model writes it and the line says so.
