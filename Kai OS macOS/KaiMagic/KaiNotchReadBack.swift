//
//  KaiNotchReadBack.swift
//  Kai OS macOS
//
//  How tall the bar must be to show a short reply.
//

import AppKit

enum KaiNotchReadBack {
    static let lineHeight: CGFloat = 18
    static let maxLines = 10
    static let font = NSFont(descriptor: NSFont.systemFont(ofSize: 13).fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.italic)
                             ?? NSFont.systemFont(ofSize: 13).fontDescriptor, size: 13) ?? NSFont.systemFont(ofSize: 13)

    /// The height of the text at this width, at most `maxLines` lines.
    static func height(of text: String, width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return min(ceil(rect.height), lineHeight * CGFloat(maxLines))
    }

    /// Bar height below the notch: the text, a row of buttons and some breathing room.
    static func barExtra(textHeight: CGFloat) -> CGFloat { textHeight + 62 }
}
