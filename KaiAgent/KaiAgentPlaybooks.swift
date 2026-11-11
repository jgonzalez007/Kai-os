//
//  KaiAgentPlaybooks.swift
//  Kai Agent
//
//  Short, hand-written notes on how to work in the apps people use most: the shortcuts that are reliable, the safest
//  way to start, and the mistake to avoid. A small model does not know these, so the note for the app in front is
//  added to the step message. They are written by hand, so they are there from the first run, before Kai has learned
//  anything from the user's own tasks.
//

import Foundation

public enum KaiAgentPlaybooks {
    private static let browser = """
    ⌘L puts the cursor in the address bar, ⌘T opens a new tab, ⌘N a new window, ⌘W closes a tab (don't). \
    To go to a site: ⌘L, type the address or the search, press return, then wait for the page to finish loading. \
    A blank page or a spinner means it is still loading: use computer_wait and look again before you click. \
    If the browser is open but has no window, press ⌘N.
    """

    static let notes: [String: (name: String, tip: String)] = [
        "com.apple.Safari": ("Safari", browser),
        "com.google.Chrome": ("Google Chrome", browser),
        "company.thebrowser.Browser": ("Arc", browser),
        "com.brave.Browser": ("Brave", browser),
        "com.microsoft.edgemac": ("Microsoft Edge", browser),
        "org.mozilla.firefox": ("Firefox", browser),
        "com.apple.mail": ("Mail", """
            ⌘N starts a new message and ⌘R replies to the selected one. Kai never sends mail: stop with the message written and say so. \
            Rules live in Mail → Settings (⌘,) → Rules. The message list is on the left and the message on the right: click a message once to read it.
            """),
        "com.tinyspeck.slackmacgap": ("Slack", """
            ⌘K opens the switcher: type a person or channel name and press return to go there. The message box is at the bottom. \
            Return SENDS the message, so press return only when the user asked you to send. To write without sending, type the text and stop.
            """),
        "com.microsoft.teams2": ("Microsoft Teams", """
            Use the search box at the top to find a person, chat or channel, then click the result. The message box is at the bottom and \
            return SENDS the message, so press return only when the user asked you to send.
            """),
        "com.apple.finder": ("Finder", """
            ⌘N opens a new window. ⇧⌘G opens "Go to Folder": type a path such as ~/Documents and press return. ⌘F searches. \
            Never delete anything or empty the Trash unless the user asked.
            """),
        "com.apple.Notes": ("Notes", "⌘N starts a new note and its first line becomes the title. Prefer the create_note tool for a simple note."),
        "com.apple.iCal": ("Calendar", "⌘N starts a new event. Prefer the add_calendar_event tool for a simple event, and read_calendar to look at the schedule."),
        "com.apple.MobileSMS": ("Messages", "⌘N starts a new message: type the name in the To field and choose the person. Return SENDS the message, so press return only when the user asked you to send."),
        "com.apple.Preview": ("Preview", "⌘F searches the document. Use the page thumbnails on the left to move around."),
    ]

    /// The note for the app in front, written as one short paragraph, or nil when there is none.
    public static func tips(forBundle bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier, let entry = notes[bundleIdentifier] else { return nil }
        let tip = entry.tip.replacingOccurrences(of: "\\\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        return "How to work in \(entry.name): \(tip.trimmingCharacters(in: .whitespaces))"
    }

    // MARK: When nothing changes

    /// What to say when an action left the screen as it was. The advice gets firmer each time it happens.
    public static func unchangedHint(count: Int) -> String {
        switch count {
        case ..<1: return ""
        case 1: return "Nothing on the screen changed after your last action. It may not have worked, or the page is still loading. Do not repeat it blindly."
        case 2: return "Nothing on the screen changed after your last two actions. Try a different way: another element, a keyboard shortcut, scrolling, a direct tool, or computer_wait if something is loading."
        default: return "The screen has not changed for \(count) actions in a row. Stop repeating. Look at the screenshot again, choose something clearly different, or call task_complete and say exactly what is blocking you."
        }
    }
}
