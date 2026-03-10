import SwiftUI
import AppKit
import os

/// Small helper that hides the dock icon as soon as the app finishes launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct NoiseNannyApp: App {
    private static let logger = Logger(subsystem: "com.noisenanny.app", category: "App")

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var engine = ScheduleEngine()
    @State private var hasBootstrapped = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(engine)
                .environment(SettingsStore.shared)
                .onAppear {
                    Task { await engine.refreshSpeakers() }
                }
        } label: {
            Image(systemName: menuBarIcon)
                .symbolRenderingMode(.hierarchical)
                .task {
                    guard !hasBootstrapped else { return }
                    hasBootstrapped = true
                    await bootstrap()
                }
        }
        .menuBarExtraStyle(.window)

        Window("NoiseNanny Settings", id: "settings") {
            SettingsView()
                .environment(engine)
                .environment(SettingsStore.shared)
        }
        .defaultSize(width: 520, height: 560)
        .keyboardShortcut(",", modifiers: .command)
    }

    private var menuBarIcon: String {
        if engine.lastError != nil {
            return "ear.trianglebadge.exclamationmark"
        }
        return engine.activeRuleCount() > 0 ? "ear.badge.waveform" : "ear"
    }

    private func bootstrap() async {
        if SettingsStore.shared.resolvedCLIPath() == nil {
            do {
                let version = try await CLIInstaller.shared.install()
                Self.logger.info("Installed sonoscli \(version)")
            } catch {
                Self.logger.warning("CLI not found and auto-install failed: \(error.localizedDescription)")
                Self.logger.info("Install manually: brew install steipete/tap/sonoscli")
            }
        } else {
            // Auto-upgrade installed CLI if a newer version is available
            do {
                let release = try await CLIInstaller.shared.latestRelease()
                let current = await CLIInstaller.shared.installedVersion() ?? ""
                let remoteVer = CLIInstaller.extractSemanticVersion(release.tagName)
                let localVer = CLIInstaller.extractSemanticVersion(current)
                if !remoteVer.isEmpty,
                   AppUpdateChecker.isNewer(remote: remoteVer, local: localVer) {
                    let version = try await CLIInstaller.shared.install()
                    Self.logger.info("Auto-updated sonoscli to \(version)")
                }
            } catch {
                Self.logger.warning("CLI update check failed: \(error.localizedDescription)")
            }
        }
        engine.start()

        if SettingsStore.shared.checkForUpdates {
            do {
                if let update = try await AppUpdateChecker.shared.checkForUpdate() {
                    engine.availableUpdate = update
                    if update.downloadURL != nil {
                        Self.logger.info("Auto-updating app to \(update.tagName)…")
                        try await AppUpdateChecker.shared.installUpdate(update)
                    }
                }
            } catch {
                Self.logger.warning("App update check failed: \(error.localizedDescription)")
            }
        }
    }
}
