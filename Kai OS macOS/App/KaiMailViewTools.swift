//
//  KaiMailViewTools.swift
//  Kai OS macOS
//
//  Chat tools for managing mail in plain words. Saved views are only filters over the inbox Kai shows, so the
//  assistant may make and remove them freely. A Mail rule changes what happens to future mail, so it is a card the
//  person approves, and it needs the "Read and organize" mailbox access.
//

import Foundation
import KaiActions
import KaiLocalAI
import KaiLocalData
import KaiShared

extension AppState {
    static let mailViewTools: [KaiOllamaTool] = [
        KaiOllamaTool(
            name: "save_mail_view",
            description: "Save a named view of the inbox that appears in the Mail page sidebar, for example 'Unread from Dana' or 'Flagged, older than a week'. It is only a filter: it changes nothing in Mail. Needs at least one condition. Saving a view with an existing name replaces it.",
            parameters: [
                .init(name: "name", type: "string", description: "A short name for the view", required: true),
                .init(name: "sender", type: "string", description: "Words in the sender's name or address", required: false),
                .init(name: "subject", type: "string", description: "Words in the subject", required: false),
                .init(name: "unread_only", type: "boolean", description: "True to show only unread messages", required: false),
                .init(name: "flagged_only", type: "boolean", description: "True to show only flagged messages", required: false),
                .init(name: "older_than_days", type: "integer", description: "Only messages received more than this many days ago", required: false),
                .init(name: "within_days", type: "integer", description: "Only messages received in the last this many days", required: false),
            ]),
        KaiOllamaTool(name: "list_mail_views", description: "List the saved mail views, with what each one shows and how many messages in the inbox match right now.", parameters: []),
        KaiOllamaTool(
            name: "remove_mail_view",
            description: "Remove a saved mail view by its name. Changes nothing in Mail.",
            parameters: [.init(name: "name", type: "string", description: "The view's name", required: true)]),
    ]

    static let mailRuleTools: [KaiOllamaTool] = [
        KaiOllamaTool(
            name: "propose_mail_rule",
            description: "Propose a rule in Apple Mail for FUTURE mail from one sender: mark it as read, or move it to a mailbox. The user sees the rule and nothing is made unless they approve. The sender must have a message in the newest part of the inbox (check with search_mail first). The rule can be removed in Mail → Settings → Rules.",
            parameters: [
                .init(name: "sender", type: "string", description: "Words in the sender's name or address, as exact as possible (an address or a domain is best)", required: true),
                .init(name: "action", type: "string", description: "mark_read or move", required: true),
                .init(name: "destination", type: "string", description: "For move: the mailbox in the same account, such as Archive", required: false),
            ]),
    ]

    private func currentMailViews() -> [KaiMailSavedView] { mailViews }

    func matchCount(_ view: KaiMailSavedView) -> Int {
        mailMessages.filter { view.matches(sender: $0.sender.isEmpty ? $0.from : $0.sender, subject: $0.subject, isRead: $0.isRead, isFlagged: $0.starred, date: $0.date) }.count
    }

    /// Adds or replaces a view and shows it in the sidebar.
    func saveMailView(_ view: KaiMailSavedView) throws {
        mailViews = try KaiMailSavedViewStore.standard.add(view)
    }

    func removeMailView(_ idOrName: String) {
        mailViews = KaiMailSavedViewStore.standard.remove(idOrName: idOrName)
    }

    /// Nil when the call isn't one of these tools.
    func mailViewTool(_ call: KaiOllamaToolCall) async throws -> String? {
        let args = call.arguments
        func flag(_ name: String) -> Bool {
            switch args[name] {
            case .bool(let value): return value
            case .string(let text): return text.lowercased() == "true"
            default: return false
            }
        }
        switch call.name {
        case "save_mail_view":
            let view = KaiMailSavedView(name: args["name"]?.stringValue ?? "", senderContains: args["sender"]?.stringValue ?? "",
                                        subjectContains: args["subject"]?.stringValue ?? "", unreadOnly: flag("unread_only"), flaggedOnly: flag("flagged_only"),
                                        olderThanDays: args["older_than_days"]?.intValue ?? 0, withinDays: args["within_days"]?.intValue ?? 0)
            do { try saveMailView(view) } catch { return error.localizedDescription }
            let saved = mailViews.first { $0.name.caseInsensitiveCompare(view.name.trimmingCharacters(in: .whitespaces)) == .orderedSame }
            return "Saved the view “\(saved?.name ?? view.name)” (\(saved?.summary ?? "")). It shows \(saved.map(matchCount) ?? 0) of the newest inbox messages now, and is in the Mail page sidebar."
        case "list_mail_views":
            guard !mailViews.isEmpty else { return "There are no saved views yet." }
            return mailViews.map { "“\($0.name)”: \($0.summary) (\(matchCount($0)) now)" }.joined(separator: "\n")
        case "remove_mail_view":
            let name = args["name"]?.stringValue ?? ""
            guard mailViews.contains(where: { $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame }) else {
                return "There is no view called “\(name)”. The views are: " + (mailViews.isEmpty ? "none" : mailViews.map(\.name).joined(separator: ", ")) + "."
            }
            removeMailView(name)
            return "Removed the view “\(name)”. Nothing in Mail changed."
        case "propose_mail_rule":
            return try await proposeMailRule(sender: args["sender"]?.stringValue ?? "", action: args["action"]?.stringValue ?? "", destination: args["destination"]?.stringValue)
        default:
            return nil
        }
    }

    private func proposeMailRule(sender raw: String, action: String, destination: String?) async throws -> String {
        guard KaiMailAccess.current.allowsChanges else {
            return "Mail access is set to “\(KaiMailAccess.current.title)”, which doesn't allow rules. Tell the user they can change it under Settings → Mailbox access."
        }
        guard mailConnected else { return "Mail is not connected. Tell the user to click Connect Mail in the Mail section of the Kai OS sidebar." }
        let key = raw.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces).lowercased()
        guard key.count >= 3, key.count <= 100 else { return "Give the sender as an address, a domain or a distinctive name (3 to 100 characters)." }
        // A rule is made from one real message of that sender, so Kai can find the account and the mailboxes.
        guard let sample = mailMessages.first(where: { ($0.sender.isEmpty ? $0.from : $0.sender).localizedCaseInsensitiveContains(key) }) else {
            return "No recent inbox message is from “\(key)”, so Kai can't make a rule for it yet. Use search_mail to find the exact sender first."
        }
        let name = KaiMailDisplay.parseSender(sample.sender.isEmpty ? sample.from : sample.sender).name
        switch action.lowercased().replacingOccurrences(of: " ", with: "_") {
        case "mark_read":
            return try propose(.mailCleanup(KaiMailCleanupPlan(operation: .rule, senderKey: key, senderName: name, items: [])))
        case "move":
            let folders = try await KaiMailCleanupRunner.folders(forMessageAt: sample.position)
            guard let folder = folders.first(where: { $0.caseInsensitiveCompare((destination ?? "").trimmingCharacters(in: .whitespaces)) == .orderedSame }) else {
                return "Pick one of these mailboxes for the move: \(folders.joined(separator: ", "))."
            }
            let item = KaiMailCleanupPlan.Item(id: sample.id, position: sample.position, subject: sample.subject)
            return try propose(.mailCleanup(KaiMailCleanupPlan(operation: .moveRule(to: folder), senderKey: key, senderName: name, items: [item])))
        default:
            return "The action must be mark_read or move."
        }
    }
}
