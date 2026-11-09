//
//  KaiPermissionsView.swift
//  Kai OS macOS
//
//  One screen for every permission Kai OS uses: what each is for, whether it's on, and a way
//  to turn it on. It appears on first launch and stays in the sidebar afterwards.
//

import AppKit
import KaiCapture
import SwiftUI

@MainActor
final class KaiPermissionsModel: ObservableObject {
    static let shared = KaiPermissionsModel()
    private static let onboardedKey = "kai.permissions.onboarded"

    @Published private(set) var statuses: [KaiPermission: KaiPermissionStatus] = [:]
    @Published private(set) var isRequestingAll = false
    @Published private(set) var requesting: KaiPermission?

    /// Replaced by the self-test, so testing never raises real prompts.
    var provider: any KaiPermissionProviding = KaiSystemPermissionProvider()
    var onGranted: ((KaiPermission) -> Void)?

    static var shouldShowOnLaunch: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["KAI_UI_SELFTEST_DIR"] != nil || environment["KAI_NOTCH_SELFTEST_DIR"] != nil { return false }
        #endif
        return !UserDefaults.standard.bool(forKey: onboardedKey)
    }

    static func markOnboarded() {
        UserDefaults.standard.set(true, forKey: onboardedKey)
    }

    var missingCount: Int { KaiPermissionPlan.missingCount(statuses: statuses) }

    func refresh() async {
        for permission in KaiPermission.allCases {
            let status = await provider.status(of: permission)
            if statuses[permission] != status {
                let wasGranted = statuses[permission] == .granted
                statuses[permission] = status
                if status == .granted && !wasGranted { onGranted?(permission) }
            }
        }
    }

    func request(_ permission: KaiPermission) {
        guard requesting == nil else { return }
        requesting = permission
        Task {
            await provider.request(permission)
            requesting = nil
            await refresh()
        }
    }

    func requestAll() {
        guard !isRequestingAll else { return }
        isRequestingAll = true
        Task {
            await refresh()
            for permission in KaiPermissionPlan.requestsForAllowAll(statuses: statuses) {
                requesting = permission
                await provider.request(permission)
                requesting = nil
                await refresh()
            }
            isRequestingAll = false
        }
    }

    func openSettings(for permission: KaiPermission) {
        if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
    }

    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

struct KaiPermissionsView: View {
    @ObservedObject var permissions: KaiPermissionsModel
    @EnvironmentObject var appState: AppState

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Permissions").font(.system(size: 30, weight: .semibold))
                        Text("Kai OS needs these to work in your other apps. Everything stays on this Mac, and you can change any of them later in System Settings.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Divider().overlay(Color.white.opacity(0.08)).padding(.bottom, 4)
                    ForEach(KaiPermission.allCases) { permission in row(permission) }
                }
                .frame(maxWidth: 780)
                .padding(.horizontal, 40).padding(.vertical, 36)
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 12) {
                Text(summary).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Allow All", action: permissions.requestAll)
                    .disabled(permissions.isRequestingAll || permissions.missingCount == 0)
                Button("Continue") {
                    KaiPermissionsModel.markOnboarded()
                    appState.activeSidebar = "Chat"
                }
                .buttonStyle(.borderedProminent)
                .tint(KaiColor.liquidBlue)
            }
            .padding(.horizontal, 40).padding(.vertical, 14)
            .background(Color.black.opacity(0.35))
            .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.08)) }
        }
        .background(KaiAmbientBackground())
        .task { await permissions.refresh() }
        .onReceive(refreshTimer) { _ in Task { await permissions.refresh() } }
    }

    private var summary: String {
        let missing = permissions.missingCount
        if missing == 0 { return "All set." }
        return "\(missing) still to turn on."
    }

    private func row(_ permission: KaiPermission) -> some View {
        let on = KaiPermissionPlan.rowAction(for: permissions.statuses[permission] ?? .notRequested) == .none
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: permission.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? KaiColor.cyan : KaiColor.magenta)
                .frame(width: 36, height: 36)
                .background(Circle().fill((on ? KaiColor.cyan : KaiColor.magenta).opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(permission.title).fontWeight(.semibold)
                Text(permission.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control(permission)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kaiLiquidGlass(on ? KaiColor.cyan : KaiColor.magenta, radius: 18, glow: on ? 0.08 : 0.2)
    }

    @ViewBuilder
    private func control(_ permission: KaiPermission) -> some View {
        let status = permissions.statuses[permission] ?? .notRequested
        if permissions.requesting == permission {
            ProgressView().controlSize(.small)
        } else {
            switch KaiPermissionPlan.rowAction(for: status) {
            case .none:
                Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(KaiColor.cyan).font(.callout)
            case .request:
                Button("Allow") { permissions.request(permission) }.disabled(permissions.requesting != nil)
            case .openSettings:
                HStack(spacing: 6) {
                    Text("Off").font(.callout).foregroundStyle(KaiColor.magenta)
                    Button("Open Settings") { permissions.openSettings(for: permission) }
                }
            case .restart:
                HStack(spacing: 6) {
                    Button("Open Settings") { permissions.openSettings(for: permission) }
                    Button("Restart Kai OS", action: permissions.relaunch)
                }
            }
        }
    }
}
