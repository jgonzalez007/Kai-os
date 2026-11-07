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
    static let primary = Color(red: 0.424, green: 0.365, blue: 0.969)
    static let primaryLight = Color(red: 0.639, green: 0.608, blue: 0.996)
    static let primaryDark = Color(red: 0.353, green: 0.294, blue: 0.816)
    static let secondary = Color(red: 0.0, green: 0.808, blue: 0.788)
    static let accent = Color(red: 0.992, green: 0.475, blue: 0.659)
    
    static let card = Color.white.opacity(0.7)
    static let cardDark = Color.black.opacity(0.3)
    static let border = Color(nsColor: .separatorColor)
    static let textPrimary = Color(nsColor: .textColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let success = Color(red: 0.0, green: 0.722, blue: 0.580)
    static let warning = Color(red: 0.988, green: 0.796, blue: 0.431)
    static let error = Color(red: 0.882, green: 0.439, blue: 0.333)
    
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceLight = Color(nsColor: .textBackgroundColor)
    
    // Dynamic (light/dark aware)
    static var cardBg: Color {
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return .black.opacity(0.3)
        } else {
            return .white.opacity(0.7)
        }
    }
    
    static var surfaceBg: Color {
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return Color(NSColor.controlBackgroundColor).opacity(0.6)
        } else {
            return Color(NSColor.controlBackgroundColor).opacity(0.3)
        }
    }
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
