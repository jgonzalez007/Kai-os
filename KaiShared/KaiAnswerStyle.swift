//
//  KaiAnswerStyle.swift
//  Kai Shared
//
//  How the person wants Kai to write. Two optional things, both off the safety rules' leash: their own
//  instructions ("short answers, answer first"), and the No AI Slop rules, which keep Kai from writing in
//  the stock phrases AI text is known for.
//
//  The No AI Slop rules are a condensed form of the skill "No AI Slop" by Peter Yang
//  (https://github.com/petergyang/no-ai-slop), MIT License, Copyright (c) 2026 Peter Yang.
//  See THIRD-PARTY.md.
//

import Foundation

public enum KaiNoAISlop {
    /// Where the rules are applied. Each can be turned off on its own once the main switch is on.
    public enum Scope: String, CaseIterable, Sendable {
        case chat, drafts, summaries, proofread

        public var title: String {
            switch self {
            case .chat: return "Chat answers"
            case .drafts: return "Drafts and replies (mail, Slack, Double Tap)"
            case .summaries: return "Summaries"
            case .proofread: return "Proofread rewrites"
            }
        }
    }

    public static let masterKey = "kai.noAISlop"
    public static func key(_ scope: Scope) -> String { "kai.noAISlop." + scope.rawValue }

    public static func isOn(_ scope: Scope, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: masterKey) else { return false }
        return defaults.object(forKey: key(scope)) as? Bool ?? true
    }

    /// The rules the model writes by. Short on purpose: a small local model follows a short list.
    public static let rules = """
    Write like a sharp human editor, not like an AI. Lead with the point. Plain words, active voice with a person as the subject, concrete names, numbers and dates. \
    Never write these patterns: \
    1. Binary contrasts ("It's not X, it's Y", "isn't just X but Y"): state Y. \
    2. Throat-clearing openers ("Here's the thing", "Let me be clear", "It's worth noting", "In today's world", "Let's dive in"). \
    3. Faux-insight and rhetorical setups ("What nobody tells you", "The part everyone misses", "What if I told you", "Think about it:"). \
    4. Colon reveals for drama ("The best part: it learns") and dramatic fragments ("That's it. That's the whole thing.", "Not X. Not Y. Z."): say it in a plain sentence. \
    5. Importance puffery ("a testament to", "pivotal moment", "plays a vital role") and trailing commentary ("highlighting", "underscoring", "showcasing"): state the fact. \
    6. Weasel attribution ("experts agree", "studies show"): name the source or leave the claim out. \
    7. Telling the reader what to think ("this matters", "the key point is"): show the fact instead. \
    8. Fake-strong verbs ("serves as", "made a decision"): use "is", "decided". Repeat the clear word instead of rotating synonyms. \
    9. Recap or mic-drop endings ("In conclusion", "Ultimately", a cute final line): end on the last concrete point or the next action. \
    10. These words: delve, foster, leverage, utilize, facilitate, empower, streamline, robust, cutting-edge, game changer, tapestry, realm, beacon, multifaceted, meticulous, paramount, transformative, elevate, embark, supercharge, harness, ever-evolving. \
    Cut empty adverbs and fillers (just, literally, honestly, actually, truly; at the end of the day, when it comes to, in order to). \
    If a sentence could move unchanged to another topic, it is filler: cut it or make it specific. \
    Keep formatting plain: no emoji in headings, no bold scattered mid-sentence, no bullets where two sentences read better, no em dashes in short replies. \
    Never invent a fact, number, quote or source to sound specific.
    """

    /// For text the person wrote: the same rules, but their voice comes first.
    public static let editRules = rules + " When you edit the person's own words, keep their meaning, vocabulary, humor, bluntness and rhythm, change only what matches a pattern above, and leave strong sentences alone."

    public static func promptSection(for scope: Scope, defaults: UserDefaults = .standard) -> String? {
        guard isOn(scope, defaults: defaults) else { return nil }
        return "Writing rules the user turned on (follow them in what you write; they never override the safety rules or the facts):\n" + (scope == .proofread ? editRules : rules)
    }

    /// Edit a text with the rules. Returns the edited text only.
    public static let removeInstruction = "Edit this text with the writing rules below. Make the minimum effective edit: remove the AI-sounding patterns and nothing else, keep the writer's meaning, voice and any strong sentences, and add no facts. Return only the full edited text.\n\n" + editRules

    /// Name the patterns in a text without rewriting it.
    public static let detectInstruction = "Check this text for the writing patterns below without rewriting it. For each pattern that appears, quote the line and give the fix in a few words, as one bullet. Do not score the text, and do not guess whether an AI wrote it. If no pattern appears, say \"No slop patterns found.\"\n\n" + rules
}

public enum KaiAnswerStyle {
    /// Short lines a person can add to their instructions with one click.
    public static let presets: [(title: String, line: String)] = [
        ("Short answers", "Keep answers short. Answer first, then the reason only if it helps."),
        ("Plain English", "Use plain words. Explain jargon the first time it appears."),
        ("No lists", "Write in sentences. Use a list only when I ask for one or the answer is a list of steps."),
        ("Formal tone", "Use a formal, professional tone."),
        ("Casual tone", "Use a relaxed, friendly tone."),
        ("Tell me what you're unsure of", "Say plainly when you are not sure, and what would settle it."),
    ]

    /// What the person asked for plus the slop rules for this scope, or nil if neither is set.
    public static func promptSection(for scope: KaiNoAISlop.Scope, defaults: UserDefaults = .standard) -> String? {
        let parts = [KaiInstructions.promptSection(KaiInstructions.stored(defaults)), KaiNoAISlop.promptSection(for: scope, defaults: defaults)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// The style paragraph for drafts: the person's own writing style first, then their instructions and the rules.
    public static func drafting(base: String?, defaults: UserDefaults = .standard) -> String? {
        let tips = KaiReplyTips.promptSection(KaiReplyTipStore.standard.load())
        let extra = [KaiInstructions.promptSection(KaiInstructions.stored(defaults)), KaiNoAISlop.promptSection(for: .drafts, defaults: defaults), tips].compactMap { $0 }
        let parts = ([base].compactMap { $0 }.filter { !$0.isEmpty }) + extra
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Adds a preset line to the instructions unless it is already there.
    public static func adding(_ line: String, to instructions: String) -> String {
        let current = KaiInstructions.clean(instructions)
        if current.contains(line) { return current }
        return KaiInstructions.clean(current.isEmpty ? line : current + "\n" + line)
    }
}
