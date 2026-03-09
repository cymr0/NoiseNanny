import SwiftUI
import AppKit

/// Small helper that hides the dock icon as soon as the app finishes launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct NoiseNannyApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var engine = ScheduleEngine()
    @State private var hasBootstrapped = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(engine)
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
                print("NoiseNanny: Installed sonoscli \(version)")
            } catch {
                print("NoiseNanny: CLI not found and auto-install failed: \(error.localizedDescription)")
                print("NoiseNanny: Install manually: brew install steipete/tap/sonoscli")
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
                    print("NoiseNanny: Auto-updated sonoscli to \(version)")
                }
            } catch {
                print("NoiseNanny: CLI update check failed: \(error.localizedDescription)")
            }
        }
        engine.start()

        if SettingsStore.shared.checkForUpdates {
            do {
                if let update = try await AppUpdateChecker.shared.checkForUpdate() {
                    engine.availableUpdate = update
                    if update.downloadURL != nil {
                        print("NoiseNanny: Auto-updating app to \(update.tagName)…")
                        try await AppUpdateChecker.shared.installUpdate(update)
                    }
                }
            } catch {
                print("NoiseNanny: App update failed: \(error.localizedDescription)")
            }
        }
    }
}
