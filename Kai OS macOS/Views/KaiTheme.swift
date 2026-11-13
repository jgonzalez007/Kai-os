//
//  KaiTheme.swift
//  Kai OS macOS
//
//  The two looks of Kai OS: Cobalt Plasma (the new one) and Classic (the one from before). The look is one setting,
//  kept in the user defaults, read by the colors and the shapes below. The Cobalt Plasma tokens come from the brand
//  files (brand_tokens.json, kai_os_cobalt_theme.css, CobaltPlasmaComponents.swift).
//

import SwiftUI

enum KaiTheme: String, CaseIterable, Identifiable {
    case cobalt, classic

    static let key = "kai.theme"
    static let `default` = KaiTheme.cobalt

    /// The look in use. Read each time, so a change shows as soon as the windows are drawn again.
    static var current: KaiTheme { KaiTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .default }
    static var isCobalt: Bool { current == .cobalt }

    var id: String { rawValue }

    var title: String { self == .cobalt ? "Hypr" : "Classic" }

    var detail: String {
        self == .cobalt
            ? "Near-black ink with one cyan accent, hairline borders, keycap chips and flat controls."
            : "The look from before: near black with cyan, violet and magenta light."
    }
}

// MARK: - Cobalt Plasma tokens

enum KaiCobalt {
    // The HyprMac palette (hyprmac.app): ink 0 to 3, one cyan accent, a hairline made from the text color.
    static let primary = Color(hex: "56D8F0")        // --cyan
    static let plasmaCyan = Color(hex: "56D8F0")     // --cyan
    static let electricBlue = Color(hex: "3BA9C0")   // a quieter cyan for tracks
    static let panel = Color(hex: "181A20")          // --ink-2
    static let sheet = Color(hex: "0A0C12")          // --ink-0
    static let ink1 = Color(hex: "101218")           // --ink-1
    static let cyanInk = Color(hex: "0B1417")        // dark text on a cyan fill
    static let magenta = Color(hex: "E84BCB")        // --magenta, the second accent
    static let text = Color(hex: "ECECF1")           // --text
    static let textSecondary = Color(hex: "9A9BA3")  // --text-soft on ink

    static let panelOpacity = 0.72
    static let sheetOpacity = 0.92
    static let borderWidth: CGFloat = 1
    static let glowRadius: CGFloat = 0
    static let cardRadius: CGFloat = 14              // --r-hud
    static let buttonRadius: CGFloat = 10

    /// --line: the text color at 12%, the border of everything.
    static var line: Color { text.opacity(0.12) }
    /// --line-soft: the text color at 7%.
    static var lineSoft: Color { text.opacity(0.07) }
    /// --cyan-dim: the cyan at 14%, the fill of a keycap.
    static var cyanDim: Color { plasmaCyan.opacity(0.14) }

    /// The press curve from the design notes: strong ease-out, quick.
    static let snap = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    static let glide = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)

    static var panelFill: Color { panel.opacity(panelOpacity) }
    static var sheetFill: Color { sheet.opacity(sheetOpacity) }
}

extension Color {
    static let kaiCobalt = KaiCobalt.primary
    static let kaiPlasmaCyan = KaiCobalt.plasmaCyan
    static let kaiElectricBlue = KaiCobalt.electricBlue
    static let kaiCobaltPanelBg = KaiCobalt.panelFill
    static let kaiCobaltSheetBg = KaiCobalt.sheetFill
    static let kaiTextSecondary = KaiCobalt.textSecondary
}

// MARK: - Glass card

/// A translucent dark blue panel with heavy blur, a gradient border in plasma cyan and a cobalt glow.
struct CobaltPlasmaGlassCard: ViewModifier {
    var borderColor: Color = .kaiPlasmaCyan
    var glowColor: Color = .kaiCobalt
    var radius: CGFloat = KaiCobalt.cardRadius

    func body(content: Content) -> some View {
        content
            // The blue panel goes over the blur (a later background sits behind an earlier one), so the card reads deep blue, not grey.
            .background(Color.kaiCobaltPanelBg, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.16), KaiCobalt.line, KaiCobalt.lineSoft], startPoint: .top, endPoint: .bottom),
                            lineWidth: KaiCobalt.borderWidth)
            )
            .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 10)
    }
}

extension View {
    func cobaltPlasmaCard(borderColor: Color = .kaiPlasmaCyan, glowColor: Color = .kaiCobalt, radius: CGFloat = KaiCobalt.cardRadius) -> some View {
        modifier(CobaltPlasmaGlassCard(borderColor: borderColor, glowColor: glowColor, radius: radius))
    }

    /// The edge of a floating panel (Today, the result card): black with a thin white edge in Classic, deep sheet blue with a plasma edge in Cobalt.
    func kaiPanelChrome(radius: CGFloat = 22) -> some View {
        modifier(KaiPanelChrome(radius: radius))
    }

    /// The main button of a view, in the look in use.
    func kaiProminent() -> some View { modifier(KaiProminentButtonModifier()) }

    /// A switch in the look in use.
    func kaiSwitch() -> some View { modifier(KaiSwitchModifier()) }

    /// The look's default controls for everything inside: plasma toggles in Cobalt Plasma, nothing changed in Classic.
    func kaiThemeRoot() -> some View { modifier(KaiThemeRootModifier()) }
}

struct KaiPanelChrome: ViewModifier {
    var radius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if KaiTheme.isCobalt {
            content
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(hex: "181818").opacity(0.96)))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: KaiCobalt.borderWidth))
                .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 14)
        } else {
            content
                .background(RoundedRectangle(cornerRadius: radius).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
    }
}

struct KaiSwitchModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if KaiTheme.isCobalt { content.toggleStyle(KaiPlasmaToggleStyle()) } else { content.toggleStyle(.switch) }
    }
}

struct KaiThemeRootModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if KaiTheme.isCobalt { content.toggleStyle(KaiPlasmaToggleStyle()).tint(KaiCobalt.plasmaCyan) } else { content }
    }
}

// MARK: - Buttons

/// The action button, like the site's Install: a solid cyan fill, dark ink text, a quick press scale.
struct KaiPlasmaButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(KaiCobalt.cyanInk)
            .background(
                RoundedRectangle(cornerRadius: KaiCobalt.buttonRadius, style: .continuous)
                    .fill(KaiCobalt.plasmaCyan.opacity(configuration.isPressed ? 0.82 : (hovering ? 0.92 : 1)))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(KaiCobalt.snap, value: configuration.isPressed)
            .animation(KaiCobalt.snap, value: hovering)
    }
}

/// The main button of a view, in the look in use.
struct KaiProminentButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if KaiTheme.isCobalt { content.buttonStyle(KaiPlasmaButtonStyle()) } else { content.buttonStyle(.borderedProminent) }
    }
}

/// A small chip in the notch: plasma outline in Cobalt Plasma, the soft white capsule in Classic.
struct KaiChipBackground: ViewModifier {
    var selected = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if KaiTheme.isCobalt {
            // A keycap, like the site's `hypr` chip: a faint cyan fill, cyan text, a thin cyan edge.
            content
                .foregroundStyle(selected ? KaiCobalt.plasmaCyan : KaiCobalt.text.opacity(0.78))
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? KaiCobalt.plasmaCyan.opacity(0.16) : KaiCobalt.lineSoft))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(selected ? KaiCobalt.plasmaCyan.opacity(0.45) : KaiCobalt.line, lineWidth: 1))
        } else {
            content
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0.09)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        }
    }
}

extension View {
    func kaiChip(selected: Bool = false) -> some View { modifier(KaiChipBackground(selected: selected)) }
}

/// A 32 by 32 tile for a status or a shortcut (Shelf, Clipboard, Stats…), with a cyan ring when it is on.
struct KaiStatusIconButton: View {
    let symbol: String
    var help: String = ""
    var active = false
    var size: CGFloat = 32
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? KaiCobalt.plasmaCyan : KaiCobalt.textSecondary)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? KaiCobalt.cyanDim : KaiCobalt.lineSoft))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(active ? KaiCobalt.plasmaCyan.opacity(0.5) : KaiCobalt.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Toggle

/// A flat switch: a cyan track with a dark thumb when on, a hairline track with a light thumb when off.
struct KaiPlasmaToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? KaiCobalt.plasmaCyan : KaiCobalt.text.opacity(0.10))
                        .overlay(Capsule().strokeBorder(configuration.isOn ? Color.clear : KaiCobalt.line, lineWidth: 1))
                    Circle()
                        .fill(configuration.isOn ? KaiCobalt.cyanInk : KaiCobalt.text.opacity(0.85))
                        .frame(width: 16, height: 16)
                        .padding(3)
                }
                .frame(width: 42, height: 22)
                .animation(KaiCobalt.glide, value: configuration.isOn)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Switch"))
            .accessibilityValue(Text(configuration.isOn ? "On" : "Off"))
        }
    }
}

// MARK: - Slider

/// A glowing slider: an electric blue track, a plasma fill and a cyan thumb. Steps snap when `step` is given.
struct KaiPlasmaSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double?

    private func fraction() -> Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let x = width * fraction()
            ZStack(alignment: .leading) {
                Capsule().fill(KaiCobalt.text.opacity(0.12)).frame(height: 4)
                Capsule().fill(KaiCobalt.plasmaCyan)
                    .frame(width: x, height: 4)
                Circle().fill(KaiCobalt.text).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .offset(x: min(max(x - 7, 0), width - 14))
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(max(drag.location.x / width, 0), 1)
                var next = range.lowerBound + f * (range.upperBound - range.lowerBound)
                if let step, step > 0 { next = range.lowerBound + ((next - range.lowerBound) / step).rounded() * step }
                value = min(max(next, range.lowerBound), range.upperBound)
            })
        }
        .frame(height: 22)
        .accessibilityRepresentation { Slider(value: $value, in: range) }
    }
}

/// A slider in the look in use.
struct KaiThemedSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double?

    var body: some View {
        if KaiTheme.isCobalt {
            KaiPlasmaSlider(value: $value, range: range, step: step)
        } else if let step {
            Slider(value: $value, in: range, step: step).tint(KaiColor.cyan)
        } else {
            Slider(value: $value, in: range).tint(KaiColor.cyan)
        }
    }
}

// MARK: - Choosing the look

/// Two tiles to pick the look, each with a small preview of its own.
struct KaiThemePicker: View {
    @AppStorage(KaiTheme.key) private var theme = KaiTheme.default.rawValue

    var body: some View {
        HStack(spacing: 14) {
            ForEach(KaiTheme.allCases) { option in
                Button { theme = option.rawValue } label: { tile(option) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func tile(_ option: KaiTheme) -> some View {
        let selected = theme == option.rawValue
        let cobalt = option == .cobalt
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(cobalt ? KaiCobalt.sheet : Color(red: 0.016, green: 0.016, blue: 0.027))
                Circle().fill(RadialGradient(colors: [(cobalt ? KaiCobalt.plasmaCyan : Color(red: 0.439, green: 0, blue: 1)).opacity(cobalt ? 0.18 : 0.5), .clear], center: .center, startRadius: 0, endRadius: 50))
                    .frame(width: 90, height: 90).offset(x: -40, y: -20)
                Circle().fill(RadialGradient(colors: [(cobalt ? KaiCobalt.plasmaCyan : KaiColor.cyan).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 40))
                    .frame(width: 70, height: 70).offset(x: 45, y: -25)
                RoundedRectangle(cornerRadius: 8)
                    .fill(cobalt ? KaiCobalt.panelFill : Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(cobalt ? KaiCobalt.line : Color.white.opacity(0.25), lineWidth: 1))
                    .frame(width: 92, height: 38)
            }
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title).fontWeight(.semibold)
                Text(option.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(selected ? 0.08 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? KaiCobalt.plasmaCyan : Color.white.opacity(0.12), lineWidth: selected ? 1.5 : 1))
    }
}

// MARK: - Segmented choice

/// A row of choices in the look in use: plasma pills in Cobalt Plasma, the system segmented control in Classic.
struct KaiThemedSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        if KaiTheme.isCobalt {
            HStack(spacing: 2) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    let selected = option.value == selection
                    Button { selection = option.value } label: {
                        Text(option.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .foregroundStyle(selected ? KaiCobalt.plasmaCyan : KaiCobalt.textSecondary)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? KaiCobalt.cyanDim : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KaiCobalt.lineSoft))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KaiCobalt.line, lineWidth: 1))
            .animation(KaiCobalt.snap, value: selection)
        } else {
            Picker("", selection: $selection) {
                ForEach(options.indices, id: \.self) { Text(options[$0].title).tag(options[$0].value) }
            }
            .pickerStyle(.segmented).labelsHidden()
        }
    }
}

/// A text box in the look in use. The system's own grey is hidden in Cobalt Plasma.
struct KaiTextBoxStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if KaiTheme.isCobalt {
            content
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KaiCobalt.panelFill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KaiCobalt.line, lineWidth: 1))
        } else {
            content.background(KaiColor.surfaceBg, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

extension View {
    func kaiTextBox() -> some View { modifier(KaiTextBoxStyle()) }
}


// MARK: - Split-flap word

/// A word as split-flap tiles, like the HYPRMAC lettering on the site: ink tiles, a hairline rim and a seam across the middle.
struct KaiFlapWord: View {
    let word: String
    var tile: CGFloat = 64

    init(_ word: String, tile: CGFloat = 64) { self.word = word; self.tile = tile }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(word.enumerated()), id: \.offset) { _, letter in
                Text(String(letter))
                    .font(.system(size: tile * 0.62, weight: .bold, design: .default))
                    .foregroundStyle(KaiCobalt.text)
                    .frame(width: tile * 0.82, height: tile)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: "262830"), Color(hex: "16181E")], startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                    .overlay(Rectangle().fill(Color.black.opacity(0.55)).frame(height: 1.5))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(word))
    }
}
