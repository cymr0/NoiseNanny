import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(ScheduleEngine.self) private var engine
    let settings = SettingsStore.shared

    @State private var selectedTab = 0
    @State private var cliStatus: String = ""
    @State private var isInstalling = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView(selection: $selectedTab) {
            volumeRulesTab
                .tabItem { Label("Volume Caps", systemImage: "speaker.wave.2") }
                .tag(0)

            autoStopTab
                .tabItem { Label("Auto-Stop", systemImage: "moon") }
                .tag(1)

            generalTab
                .tabItem { Label("General", systemImage: "gear") }
                .tag(2)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 500)
        .onAppear { checkCLI() }
    }

    // MARK: - Volume Rules Tab

    private var volumeRulesTab: some View {
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
                ForEach(settings.volumeRules) { rule in
                    if let idx = settings.volumeRules.firstIndex(where: { $0.id == rule.id }) {
                        VolumeRuleEditor(
                            rule: Binding(
                                get: { settings.volumeRules[idx] },
                                set: { settings.volumeRules[idx] = $0 }
                            ),
                            targets: engine.allTargets,
                            onDelete: { settings.volumeRules.removeAll { $0.id == rule.id } }
                        )
                    }
                }
            }
            .listStyle(.bordered)
        }
    }

    // MARK: - Auto-Stop Tab

    private var autoStopTab: some View {
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
                ForEach(settings.autoStopRules) { rule in
                    if let idx = settings.autoStopRules.firstIndex(where: { $0.id == rule.id }) {
                        AutoStopRuleEditor(
                            rule: Binding(
                                get: { settings.autoStopRules[idx] },
                                set: { settings.autoStopRules[idx] = $0 }
                            ),
                            targets: engine.allTargets,
                            onDelete: { settings.autoStopRules.removeAll { $0.id == rule.id } }
                        )
                    }
                }
            }
            .listStyle(.bordered)
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Polling") {
                HStack {
                    Text("Poll interval:")
                    TextField(
                        "",
                        value: Binding(
                            get: { settings.pollInterval },
                            set: { settings.pollInterval = max(5, $0) }
                        ),
                        format: .number
                    )
                    .frame(width: 60)
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

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("NoiseNanny: Failed to update login item: \(error.localizedDescription)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("About") {
                Text("NoiseNanny — Sonos volume enforcer")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - CLI helpers

    private func checkCLI() {
        if let path = settings.resolvedCLIPath() {
            Task {
                let ver = await CLIInstaller.shared.installedVersion()
                cliStatus = ver ?? "Installed at \(path)"
            }
        } else {
            cliStatus = "Not installed"
        }
    }

    private func installCLI() {
        isInstalling = true
        Task {
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
        Task {
            do {
                let release = try await CLIInstaller.shared.latestRelease()
                let current = await CLIInstaller.shared.installedVersion() ?? ""
                let remoteVer = CLIInstaller.extractSemanticVersion(release.tagName)
                let localVer = CLIInstaller.extractSemanticVersion(current)
                if remoteVer != localVer && !remoteVer.isEmpty {
                    cliStatus = "Update available: \(release.tagName) (current: \(current))"
                } else {
                    cliStatus = "Up to date (\(release.tagName))"
                }
            } catch {
                cliStatus = "Check failed: \(error.localizedDescription)"
            }
            isInstalling = false
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
                Toggle("", isOn: $rule.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Picker("Target:", selection: $rule.speakerName) {
                    Text("All Speakers").tag("")
                    if !rule.speakerName.isEmpty,
                       !targets.contains(where: { $0.speakerName == rule.speakerName }) {
                        Text(rule.speakerName).tag(rule.speakerName)
                    }
                    ForEach(targets) { target in
                        Text(target.label).tag(target.speakerName)
                    }
                }
                .frame(maxWidth: 180)
                .onChange(of: rule.speakerName) { _, newValue in
                    rule.targetGroupId = targets.first { $0.speakerName == newValue }?.groupId
                }

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Text("Max volume:")
                Slider(value: Binding(
                    get: { Double(rule.maxVolume) },
                    set: { rule.maxVolume = Int($0) }
                ), in: 0...100, step: 5)
                Text("\(rule.maxVolume)%")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }

            HStack {
                Text("From")
                TimePickerCompact(hour: $rule.startHour, minute: $rule.startMinute)
                Text("to")
                TimePickerCompact(hour: $rule.endHour, minute: $rule.endMinute)
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
                Toggle("", isOn: $rule.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Picker("Target:", selection: $rule.speakerName) {
                    Text("All Speakers").tag("")
                    if !rule.speakerName.isEmpty,
                       !targets.contains(where: { $0.speakerName == rule.speakerName }) {
                        Text(rule.speakerName).tag(rule.speakerName)
                    }
                    ForEach(targets) { target in
                        Text(target.label).tag(target.speakerName)
                    }
                }
                .frame(maxWidth: 180)
                .onChange(of: rule.speakerName) { _, newValue in
                    rule.targetGroupId = targets.first { $0.speakerName == newValue }?.groupId
                }

                Spacer()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Text("Quiet from")
                TimePickerCompact(hour: $rule.startHour, minute: $rule.startMinute)
                Text("to")
                TimePickerCompact(hour: $rule.endHour, minute: $rule.endMinute)
            }
        }
        .padding(.vertical, 4)
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

struct TimePickerCompact: View {
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        HStack(spacing: 2) {
            Picker("", selection: $hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .frame(width: 55)
            .labelsHidden()

            Text(":")

            Picker("", selection: $minute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .frame(width: 55)
            .labelsHidden()
        }
    }
}
