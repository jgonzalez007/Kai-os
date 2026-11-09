//
//  KaiDesignSystem.swift
//  Kai OS macOS
//
//  Visual design system — colors, typography, spacing, and style modifiers
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI

// MARK: - Colors

struct KaiColor {
    // Brand colors (brand_color_system): electric cyan, liquid blue, deep violet, neon magenta.
    static let cyan = Color(red: 0.0, green: 0.878, blue: 1.0)            // #00E0FF (asset package)
    static let liquidBlue = Color(red: 0.227, green: 0.525, blue: 1.0)    // #3A86FF
    static let violet = Color(red: 0.439, green: 0.0, blue: 1.0)          // #7000FF
    static let magenta = Color(red: 1.0, green: 0.0, blue: 0.498)         // #FF007F (asset package)

    static let primary = liquidBlue
    static let primaryLight = cyan
    static let primaryDark = violet
    static let secondary = cyan
    static let accent = magenta
    
    static let card = Color.white.opacity(0.7)
    static let cardDark = Color.black.opacity(0.3)
    static let border = Color.white.opacity(0.18)
    static let textPrimary = Color(nsColor: .textColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let success = Color(red: 0.0, green: 0.722, blue: 0.580)
    static let warning = Color(red: 0.988, green: 0.796, blue: 0.431)
    static let error = Color(red: 0.882, green: 0.439, blue: 0.333)
    
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceLight = Color(nsColor: .textBackgroundColor)
    
    // Kai OS is always dark now: cards are a faint lift on the near-black window.
    static var cardBg: Color { Color.white.opacity(0.05) }
    static var surfaceBg: Color { Color.white.opacity(0.05) }
    static let windowBg = Color(red: 0.016, green: 0.016, blue: 0.027)   // near black, #040407
    static let panelBg = Color(red: 0.176, green: 0.227, blue: 0.310)    // #2D3A4F
    static let textBase = Color(red: 0.878, green: 0.878, blue: 0.878)   // #E0E0E0
}

extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        
        let hex = Int64(hexString, radix: 16)
        guard let hex = hex, hexString.count == 6 else { self = .black; return }
        
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        
        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Typography

enum KaiFont {
    static let title1 = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let title3 = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 14, weight: .regular, design: .rounded)
    static let bodyStrong = Font.system(size: 14, weight: .medium, design: .rounded)
    static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
    static let captionStrong = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let caption2 = Font.system(size: 11, weight: .medium, design: .rounded)
    static let caption2Strong = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let caption3 = Font.system(size: 10, weight: .medium, design: .rounded)
    
    static let label = Font.system(size: 13, weight: .medium, design: .rounded)
    static let labelStrong = Font.system(size: 13, weight: .semibold, design: .rounded)
}

// MARK: - Spacing

enum KaiSpacing {
    static let tiny = CGFloat(4)
    static let small = CGFloat(8)
    static let medium = CGFloat(12)
    static let regular = CGFloat(16)
    static let large = CGFloat(20)
    static let xlarge = CGFloat(24)
    static let xxlarge = CGFloat(32)
    static let sidebarPadding = CGFloat(12)
    static let cardPadding = CGFloat(16)
    static let cornerRadius = CGFloat(12)
    static let cornerRadiusSmall = CGFloat(8)
    static let cornerRadiusLarge = CGFloat(16)
    static let inputRadius = CGFloat(14)
}

// MARK: - Style Modifiers

struct KaiCardBackground: ViewModifier {
    var padding: CGFloat = KaiSpacing.cardPadding
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                    .fill(KaiColor.cardBg)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                            .stroke(KaiColor.border.opacity(0.5), lineWidth: 0.5)
                    )
            )
    }
}

struct KaiGradientCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(KaiSpacing.cardPadding)
            .background(
                LinearGradient(
                    colors: [KaiColor.primary.opacity(0.08), KaiColor.secondary.opacity(0.05)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(0.5)
                .cornerRadius(KaiSpacing.cornerRadiusLarge)
                .overlay(
                    RoundedRectangle(cornerRadius: KaiSpacing.cornerRadiusLarge)
                        .stroke(KaiColor.primary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: KaiColor.primary.opacity(0.08), radius: 10, x: 0, y: 4)
            )
    }
}

struct KaiInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(KaiSpacing.regular)
            .background(
                RoundedRectangle(cornerRadius: KaiSpacing.inputRadius)
                    .fill(KaiColor.surfaceBg)
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: KaiSpacing.inputRadius)
                            .strokeBorder(KaiColor.border.opacity(0.4), lineWidth: 1)
                    )
            )
    }
}

struct KaiSectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(KaiFont.caption2Strong)
            .foregroundStyle(KaiColor.textTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, KaiSpacing.regular)
            .padding(.top, KaiSpacing.large)
    }
}

struct KaiDividerStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, KaiSpacing.regular)
            .opacity(0.3)
    }
}

extension View {
    func kaiCard() -> some View {
        modifier(KaiCardBackground())
    }
    
    func kaiGradientCard() -> some View {
        modifier(KaiGradientCardBackground())
    }
    
    func kaiInput() -> some View {
        modifier(KaiInputStyle())
    }
    
    func kaiSectionHeader() -> some View {
        modifier(KaiSectionHeaderStyle())
    }
    
    func kaiDivider() -> some View {
        modifier(KaiDividerStyle())
    }
    
    func kaiSidebarItem(active: Bool) -> some View {
        self
            .padding(.horizontal, KaiSpacing.sidebarPadding)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: KaiSpacing.cornerRadiusSmall)
                    .fill(active ? KaiColor.primary.opacity(0.12) : Color.clear)
            )
            .foregroundStyle(active ? KaiColor.primary : KaiColor.textPrimary)
    }
    
    func kaiGlow(opacity: Double = 0.5) -> some View {
        self.shadow(color: KaiColor.primary.opacity(opacity), radius: 12, x: 0, y: 0)
    }
}

// MARK: - Animated Divider

struct KaiAnimatedDivider: View {
    var color: Color = KaiColor.border
    var height: CGFloat = 1
    
    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [color.opacity(0.6), color.opacity(0.05), color.opacity(0.0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: height)
            .frame(width: geo.size.width / 3)
        }
        .frame(height: height)
    }
}

// MARK: - Activity Indicator

struct KaiActivityView: View {
    var size: CGFloat = 20
    var color: Color = KaiColor.primary
    
    var body: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: color))
            .scaleEffect(size / 20)
    }
}

// MARK: - Status Badge

struct KaiStatusBadge: View {
    let status: String
    let icon: String
    let color: Color
    
    var body: some View {
        Label(status, systemImage: icon)
            .font(KaiFont.caption2Strong)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Icon Button

struct KaiIconButton: View {
    let icon: String
    let action: () -> Void
    var tint: Color = .secondary
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Primary Button

struct KaiPrimaryButton: View {
    let title: String
    var action: () -> Void
    
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle)
    }
}

// MARK: - Ghost Button

struct KaiGhostButton: View {
    let title: String
    var action: () -> Void
    
    var body: some View {
        Button(title, action: action)
            .foregroundStyle(KaiColor.primary)
    }
}

// MARK: - Source Error Banner

struct KaiSourceErrorBanner: View {
    let state: KaiSourceState

    var body: some View {
        if case .failed(let message) = state {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(KaiFont.caption)
                .foregroundStyle(KaiColor.error)
                .padding(.horizontal, KaiSpacing.regular)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Connect Card

struct KaiConnectCard: View {
    let title: String
    let icon: String
    let explanation: String
    let state: KaiSourceState
    let connect: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(KaiFont.title2)
                .foregroundStyle(KaiColor.primary)
                .kaiGlow()
            
            Text("Connect \\(title)").font(KaiFont.title3).fontWeight(.bold)
            
            Text(explanation)
                .font(KaiFont.caption)
                .foregroundStyle(KaiColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            if case .failed(let message) = state {
                Text(message)
                    .font(KaiFont.caption)
                    .foregroundStyle(KaiColor.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)
            }
            
            if state == .loading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: KaiColor.primary))
                    .scaleEffect(0.7)
            } else {
                Button("Connect \\(title)", action: connect)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
            }
        }
        .padding(KaiSpacing.xxlarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Attach Screen Button

struct KaiAttachScreenButton: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Button(action: appState.attachScreen) {
            if appState.isCapturingScreen {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: KaiColor.primary))
                    .scaleEffect(0.6)
            } else {
                Image(systemName: appState.pendingScreenshot == nil ? "camera.viewfinder" : "checkmark.rectangle.fill")
                    .font(KaiFont.labelStrong)
                    .foregroundStyle(appState.pendingScreenshot == nil ? KaiColor.textSecondary : KaiColor.primary)
            }
        }
        .buttonStyle(.plain)
        .help("Attach a screenshot of this display to your next message")
    }
}

// MARK: - Pending Screenshot Chip

struct KaiPendingScreenshotChip: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let data = appState.pendingScreenshot, let image = NSImage(data: data) {
            HStack(spacing: 10) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 36)
                    .cornerRadius(KaiSpacing.cornerRadiusSmall)
                
                Text("Screen attached").font(KaiFont.captionStrong)
                    .foregroundStyle(KaiColor.textSecondary)
                
                Button { appState.pendingScreenshot = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KaiColor.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Remove the screenshot")
                
                Spacer()
            }
            .padding(KaiSpacing.small)
            .background(KaiColor.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius))
        }
    }
}


// MARK: - Liquid glass

/// The brand's glass surface: a frosted fill, a bright hairline that is strongest at the top edge, a
/// soft inner highlight and a deep shadow.
struct KaiGlass: ViewModifier {
    var radius: CGFloat = 18
    var fill: Double = 0.06

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(fill))
                }
                .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.10), Color.white.opacity(0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .top) {
                // The specular line along the top edge.
                Capsule().fill(Color.white.opacity(0.28)).frame(height: 1)
                    .padding(.horizontal, radius).padding(.top, 0.5)
                    .blur(radius: 0.4)
            }
    }
}

extension View {
    func kaiGlassSurface(radius: CGFloat = 18, fill: Double = 0.06) -> some View {
        modifier(KaiGlass(radius: radius, fill: fill))
    }
}

/// The window background: near-black with soft cyan, violet and magenta light behind it, so the glass
/// has something to frost.
struct KaiAmbientBackground: View {
    var body: some View {
        ZStack {
            KaiColor.windowBg
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    // Black, with light coming in from the top: violet and magenta on the left, cyan on the right.
                    glow(KaiColor.violet, opacity: 0.30, diameter: w * 0.85).position(x: w * 0.05, y: -h * 0.05)
                    glow(KaiColor.magenta, opacity: 0.20, diameter: w * 0.55).position(x: w * 0.30, y: -h * 0.12)
                    glow(KaiColor.cyan, opacity: 0.17, diameter: w * 0.65).position(x: w * 0.98, y: -h * 0.05)
                    glow(KaiColor.liquidBlue, opacity: 0.08, diameter: w * 0.9).position(x: w * 0.5, y: h * 1.15)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// A soft light made with a radial fade, so it looks the same everywhere without relying on blur.
    private func glow(_ color: Color, opacity: Double, diameter: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.35), .clear],
                                 center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - Liquid glass card (asset package)

/// The package's card: frosted material under a blue-gray panel color at 75%, a 1.5 point border that
/// fades from the accent color, and a soft glow in that color. Cyan by default, magenta for contrast.
struct KaiLiquidGlassCard: ViewModifier {
    var accent: Color = KaiColor.cyan
    var radius: CGFloat = 16
    var glowStrength: Double = 0.35

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(KaiColor.panelBg.opacity(0.75), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LinearGradient(colors: [accent.opacity(0.8), accent.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            )
            .shadow(color: accent.opacity(glowStrength), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func kaiLiquidGlass(_ accent: Color = KaiColor.cyan, radius: CGFloat = 16, glow: Double = 0.35) -> some View {
        modifier(KaiLiquidGlassCard(accent: accent, radius: radius, glowStrength: glow))
    }
}
