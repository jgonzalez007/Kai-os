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

    var title: String { self == .cobalt ? "Cobalt Plasma" : "Classic" }

    var detail: String {
        self == .cobalt
            ? "Deep blue glass with cyan plasma light, glowing borders, toggles and sliders."
            : "The look from before: near black with cyan, violet and magenta light."
    }
}

// MARK: - Cobalt Plasma tokens

enum KaiCobalt {
    static let primary = Color(hex: "0066FF")
    static let plasmaCyan = Color(hex: "00E0FF")
    static let electricBlue = Color(hex: "1A8CFF")
    static let panel = Color(hex: "0D1B2A")
    static let sheet = Color(hex: "050B14")
    static let textSecondary = Color(hex: "8A99AD")

    static let panelOpacity = 0.80
    static let sheetOpacity = 0.90
    static let borderWidth: CGFloat = 1.5
    static let glowRadius: CGFloat = 16
    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 10

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
                    .stroke(LinearGradient(colors: [borderColor.opacity(0.8), glowColor.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: KaiCobalt.borderWidth)
            )
            .shadow(color: glowColor.opacity(0.4), radius: 14, x: 0, y: 0)
            .shadow(color: borderColor.opacity(0.2), radius: 6, x: 0, y: 0)
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
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(KaiCobalt.sheet.opacity(0.97)))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [KaiCobalt.plasmaCyan.opacity(0.7), KaiCobalt.primary.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: KaiCobalt.borderWidth))
                .shadow(color: KaiCobalt.primary.opacity(0.45), radius: KaiCobalt.glowRadius)
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

/// The action button: a cobalt to cyan wash, a cyan edge and a glow that grows under the pointer.
struct KaiPlasmaButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let strong = configuration.isPressed || hovering
        return configuration.label
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: KaiCobalt.buttonRadius, style: .continuous)
                    .fill(LinearGradient(colors: [KaiCobalt.primary.opacity(strong ? 0.45 : 0.25), KaiCobalt.plasmaCyan.opacity(strong ? 0.30 : 0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: KaiCobalt.buttonRadius, style: .continuous).strokeBorder(KaiCobalt.plasmaCyan, lineWidth: 1))
            .shadow(color: KaiCobalt.plasmaCyan.opacity(strong ? 0.6 : 0.3), radius: strong ? 9 : 6)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(.easeInOut(duration: 0.2), value: strong)
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
            content
                .background(Capsule().fill(LinearGradient(colors: [KaiCobalt.primary.opacity(selected ? 0.55 : 0.25), KaiCobalt.plasmaCyan.opacity(selected ? 0.35 : 0.12)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Capsule().strokeBorder(KaiCobalt.plasmaCyan.opacity(selected ? 0.9 : 0.5), lineWidth: 0.75))
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? KaiCobalt.plasmaCyan : KaiCobalt.textSecondary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KaiCobalt.panelFill))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(active ? KaiCobalt.plasmaCyan : KaiCobalt.textSecondary.opacity(0.3), lineWidth: active ? 1.5 : 1))
                .shadow(color: active ? KaiCobalt.plasmaCyan.opacity(0.5) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Toggle

/// A neon switch: a glowing cobalt track and a cyan thumb when on, a dim track and a grey thumb when off.
struct KaiPlasmaToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 8)
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn
                              ? AnyShapeStyle(LinearGradient(colors: [KaiCobalt.primary.opacity(0.75), KaiCobalt.electricBlue.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                              : AnyShapeStyle(KaiCobalt.panelFill))
                        .overlay(Capsule().strokeBorder(configuration.isOn ? KaiCobalt.plasmaCyan : KaiCobalt.textSecondary.opacity(0.45), lineWidth: 1))
                        .shadow(color: configuration.isOn ? KaiCobalt.plasmaCyan.opacity(0.45) : .clear, radius: 6)
                    Circle()
                        .fill(configuration.isOn ? KaiCobalt.plasmaCyan : KaiCobalt.textSecondary)
                        .frame(width: 16, height: 16)
                        .shadow(color: configuration.isOn ? KaiCobalt.plasmaCyan.opacity(0.9) : .clear, radius: 5)
                        .padding(3)
                }
                .frame(width: 42, height: 22)
                .animation(.easeInOut(duration: 0.18), value: configuration.isOn)
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
                Capsule().fill(KaiCobalt.electricBlue.opacity(0.25)).frame(height: 4)
                Capsule().fill(LinearGradient(colors: [KaiCobalt.primary, KaiCobalt.plasmaCyan], startPoint: .leading, endPoint: .trailing))
                    .frame(width: x, height: 4)
                    .shadow(color: KaiCobalt.plasmaCyan.opacity(0.6), radius: 5)
                Circle().fill(KaiCobalt.plasmaCyan).frame(width: 14, height: 14)
                    .shadow(color: KaiCobalt.plasmaCyan.opacity(0.9), radius: 6)
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
                Circle().fill(RadialGradient(colors: [(cobalt ? KaiCobalt.primary : Color(red: 0.439, green: 0, blue: 1)).opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 50))
                    .frame(width: 90, height: 90).offset(x: -40, y: -20)
                Circle().fill(RadialGradient(colors: [(cobalt ? KaiCobalt.plasmaCyan : KaiColor.cyan).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 40))
                    .frame(width: 70, height: 70).offset(x: 45, y: -25)
                RoundedRectangle(cornerRadius: 8)
                    .fill(cobalt ? KaiCobalt.panelFill : Color.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(cobalt ? KaiCobalt.plasmaCyan.opacity(0.7) : Color.white.opacity(0.25), lineWidth: cobalt ? 1.5 : 1))
                    .shadow(color: cobalt ? KaiCobalt.primary.opacity(0.6) : .clear, radius: 8)
                    .frame(width: 92, height: 38)
            }
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(option.title + (option == .cobalt ? " (new)" : "")).fontWeight(.semibold)
                Text(option.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(selected ? 0.08 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? KaiCobalt.plasmaCyan : Color.white.opacity(0.12), lineWidth: selected ? 1.5 : 1))
    }
}
