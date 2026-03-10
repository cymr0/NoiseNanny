import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            VolumeRulesTab()
                .tabItem { Label("Volume Caps", systemImage: "speaker.wave.2") }
                .tag(0)

            AutoStopTab()
                .tabItem { Label("Auto-Stop", systemImage: "moon") }
                .tag(1)

            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(2)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 500)
    }
}

// MARK: - Volume Rules Tab

private struct VolumeRulesTab: View {
    @Environment(ScheduleEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let bindableSettings = Bindable(settings)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Volume Cap Rules")
                    .font(.headline)
                Spacer()
                Button {
                    settings.volumeRules.append(VolumeRule())
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }

            Text("When a rule is active, speaker volumes exceeding the cap are automatically reduced.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(bindableSettings.volumeRules) { $rule in
                    VolumeRuleEditor(
                        rule: $rule,
                        targets: engine.allTargets,
                        onDelete: { settings.volumeRules.removeAll { $0.id == rule.id } }
                    )
                }
            }
            .listStyle(.bordered)
        }
    }
}

// MARK: - Auto-Stop Tab

private struct AutoStopTab: View {
    @Environment(ScheduleEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let bindableSettings = Bindable(settings)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Auto-Stop Rules")
                    .font(.headline)
                Spacer()
                Button {
                    settings.autoStopRules.append(AutoStopRule())
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }

            Text("Stops playback on selected speakers during the quiet window. Music restarted during this window will be stopped again.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(bindableSettings.autoStopRules) { $rule in
                    AutoStopRuleEditor(
                        rule: $rule,
                        targets: engine.allTargets,
                        onDelete: { settings.autoStopRules.removeAll { $0.id == rule.id } }
                    )
                }
            }
            .listStyle(.bordered)
        }
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Environment(ScheduleEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings

    @State private var cliStatus: String = ""
    @State private var isInstalling = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var appUpdateStatus: String = ""
    @State private var isCheckingAppUpdate = false
    @State private var loginItemError: String = ""

    var body: some View {
        let bindableSettings = Bindable(settings)

        Form {
            Section("Polling") {
                HStack {
                    Text("Poll interval:")
                    TextField("", value: bindableSettings.pollInterval, format: .number)
                        .frame(width: 60)
                        .onChange(of: settings.pollInterval) { _, newValue in
                            if newValue < 5 { settings.pollInterval = 5 }
                        }
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
            }

            Section("CLI Binary") {
                HStack {
                    Text("Path:")
                    Text(settings.resolvedCLIPath() ?? "Not found")
                        .foregroundStyle(settings.resolvedCLIPath() != nil ? Color.primary : Color.red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("Status:")
                    Text(cliStatus)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(settings.resolvedCLIPath() != nil ? "Reinstall from GitHub" : "Install from GitHub") {
                        installCLI()
                    }
                    .disabled(isInstalling)

                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button("Check for Update") {
                        checkForUpdate()
                    }
                    .disabled(isInstalling)
                }
            }

            Section("App Updates") {
                Toggle("Check for updates on launch", isOn: Binding(
                    get: { settings.checkForUpdates },
                    set: { settings.checkForUpdates = $0 }
                ))

                if !appUpdateStatus.isEmpty {
                    Text(appUpdateStatus)
                        .foregroundStyle(.secondary)
                }

                if let update = engine.availableUpdate {
                    HStack {
                        Label("New version: \(update.tagName)", systemImage: "arrow.down.circle")
                            .foregroundStyle(.blue)
                        Spacer()
                        Button("View Release") {
                            if let url = URL(string: update.htmlURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }

                HStack {
                    Button("Check Now") {
                        checkForAppUpdate()
                    }
                    .disabled(isCheckingAppUpdate)

                    if isCheckingAppUpdate {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginItemError = ""
                        } catch {
                            loginItemError = "Failed to update login item: \(error.localizedDescription)"
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                if !loginItemError.isEmpty {
                    Text(loginItemError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("About") {
                Text("NoiseNanny — Sonos volume enforcer")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { checkCLI() }
    }

    // MARK: - App update helpers

    private func checkForAppUpdate() {
        isCheckingAppUpdate = true
        appUpdateStatus = ""
        Task { @MainActor in
            do {
                if let update = try await AppUpdateChecker.shared.checkForUpdate() {
                    engine.availableUpdate = update
                    if update.downloadURL != nil {
                        appUpdateStatus = "Installing \(update.tagName)…"
                        try await AppUpdateChecker.shared.installUpdate(update)
                    } else {
                        appUpdateStatus = "Update available but no download asset found"
                    }
                } else {
                    engine.availableUpdate = nil
                    let version = await AppUpdateChecker.shared.currentVersion
                    appUpdateStatus = "Up to date (v\(version))"
                }
            } catch {
                appUpdateStatus = "Update failed: \(error.localizedDescription)"
            }
            isCheckingAppUpdate = false
        }
    }

    // MARK: - CLI helpers

    private func checkCLI() {
        if let path = settings.resolvedCLIPath() {
            Task { @MainActor in
                let ver = await CLIInstaller.shared.installedVersion()
                cliStatus = ver ?? "Installed at \(path)"
            }
        } else {
            cliStatus = "Not installed"
        }
    }

    private func installCLI() {
        isInstalling = true
        Task { @MainActor in
            do {
                let version = try await CLIInstaller.shared.install()
                cliStatus = "Installed \(version)"
            } catch {
                cliStatus = "Install failed: \(error.localizedDescription)"
            }
            isInstalling = false
        }
    }

    private func checkForUpdate() {
        isInstalling = true
        Task { @MainActor in
            do {
                let release = try await CLIInstaller.shared.latestRelease()
                let current = await CLIInstaller.shared.installedVersion() ?? ""
                let remoteVer = CLIInstaller.extractSemanticVersion(release.tagName)
                let localVer = CLIInstaller.extractSemanticVersion(current)
                if !remoteVer.isEmpty,
                   AppUpdateChecker.isNewer(remote: remoteVer, local: localVer) {
                    cliStatus = "Updating to \(release.tagName)…"
                    let version = try await CLIInstaller.shared.install()
                    cliStatus = "Updated to \(version)"
                } else {
                    cliStatus = "Up to date (\(release.tagName))"
                }
            } catch {
                cliStatus = "Update failed: \(error.localizedDescription)"
            }
            isInstalling = false
        }
    }
}

// MARK: - Rule Target Picker (shared between both editors)

private struct RuleTargetPicker: View {
    @Binding var speakerName: String
    @Binding var targetGroupId: String?
    let targets: [RuleTarget]

    var body: some View {
        Picker("Target:", selection: $speakerName) {
            Text("All Speakers").tag("")
            if !speakerName.isEmpty,
               !targets.contains(where: { $0.speakerName == speakerName }) {
                Text(speakerName).tag(speakerName)
            }
            ForEach(targets) { target in
                Text(target.label).tag(target.speakerName)
            }
        }
        .frame(maxWidth: 180)
        .onChange(of: speakerName) { _, newValue in
            targetGroupId = targets.first { $0.speakerName == newValue }?.groupId
        }
    }
}

// MARK: - Rule Editors

struct VolumeRuleEditor: View {
    @Binding var rule: VolumeRule
    let targets: [RuleTarget]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Enabled", isOn: $rule.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Rule enabled")
                    .accessibilityHint("Toggles this volume cap rule on or off")

                RuleTargetPicker(
                    speakerName: $rule.speakerName,
                    targetGroupId: $rule.targetGroupId,
                    targets: targets
                )

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete rule")
                .accessibilityHint("Permanently removes this volume cap rule")
            }

            HStack {
                Text("Max volume:")
                Slider(value: Binding(
                    get: { Double(rule.maxVolume) },
                    set: { rule.maxVolume = Int($0) }
                ), in: 0...100, step: 5)
                .accessibilityLabel("Maximum volume")
                .accessibilityValue("\(rule.maxVolume) percent")
                Text("\(rule.maxVolume)%")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
                    .accessibilityHidden(true)
            }

            HStack {
                Text("From")
                TimePickerCompact(hour: $rule.startHour, minute: $rule.startMinute, label: "Start time")
                Text("to")
                TimePickerCompact(hour: $rule.endHour, minute: $rule.endMinute, label: "End time")
            }
        }
        .padding(.vertical, 4)
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

struct AutoStopRuleEditor: View {
    @Binding var rule: AutoStopRule
    let targets: [RuleTarget]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Enabled", isOn: $rule.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Rule enabled")
                    .accessibilityHint("Toggles this auto-stop rule on or off")

                RuleTargetPicker(
                    speakerName: $rule.speakerName,
                    targetGroupId: $rule.targetGroupId,
                    targets: targets
                )

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete rule")
                .accessibilityHint("Permanently removes this auto-stop rule")
            }

            HStack {
                Text("Quiet from")
                TimePickerCompact(hour: $rule.startHour, minute: $rule.startMinute, label: "Quiet start time")
                Text("to")
                TimePickerCompact(hour: $rule.endHour, minute: $rule.endMinute, label: "Quiet end time")
            }
        }
        .padding(.vertical, 4)
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

// MARK: - Time Picker

struct TimePickerCompact: View {
    @Binding var hour: Int
    @Binding var minute: Int
    var label: String = "Time"

    var body: some View {
        HStack(spacing: 2) {
            Picker("", selection: $hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .frame(width: 55)
            .labelsHidden()
            .accessibilityLabel("\(label) hour")
            .accessibilityValue(String(format: "%02d", hour))

            Text(":")
                .accessibilityHidden(true)

            Picker("", selection: $minute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .frame(width: 55)
            .labelsHidden()
            .accessibilityLabel("\(label) minute")
            .accessibilityValue(String(format: "%02d", minute))
        }
    }
}
