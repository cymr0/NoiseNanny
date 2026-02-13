import SwiftUI

struct SettingsView: View {
    @Environment(ScheduleEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings

    @State private var selectedTab = 0
    @State private var cliStatus: String = ""
    @State private var isInstalling = false

    var body: some View {
        @Bindable var settings = settings

        TabView(selection: $selectedTab) {
            volumeRulesTab(settings: $settings)
                .tabItem { Label("Volume Caps", systemImage: "speaker.wave.2") }
                .tag(0)

            autoStopTab(settings: $settings)
                .tabItem { Label("Auto-Stop", systemImage: "moon") }
                .tag(1)

            generalTab(settings: $settings)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(2)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 500)
        .onAppear { checkCLI() }
    }

    // MARK: - Volume Rules Tab

    private func volumeRulesTab(settings: Bindable<SettingsStore>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Volume Cap Rules")
                    .font(.headline)
                Spacer()
                Button {
                    self.settings.volumeRules.append(VolumeRule())
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }

            Text("When a rule is active, speaker volumes exceeding the cap are automatically reduced.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(settings.$volumeRules) { $rule in
                    VolumeRuleEditor(
                        rule: $rule,
                        targets: engine.allTargets,
                        onDelete: { self.settings.volumeRules.removeAll { $0.id == rule.id } }
                    )
                }
            }
            .listStyle(.bordered)
        }
    }

    // MARK: - Auto-Stop Tab

    private func autoStopTab(settings: Bindable<SettingsStore>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Auto-Stop Rules")
                    .font(.headline)
                Spacer()
                Button {
                    self.settings.autoStopRules.append(AutoStopRule())
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }

            Text("Stops playback on selected speakers during the quiet window. Music restarted during this window will be stopped again.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(settings.$autoStopRules) { $rule in
                    AutoStopRuleEditor(
                        rule: $rule,
                        targets: engine.allTargets,
                        onDelete: { self.settings.autoStopRules.removeAll { $0.id == rule.id } }
                    )
                }
            }
            .listStyle(.bordered)
        }
    }

    // MARK: - General Tab

    private func generalTab(settings: Bindable<SettingsStore>) -> some View {
        Form {
            Section("Polling") {
                HStack {
                    Text("Poll interval:")
                    TextField("", value: settings.$pollInterval, format: .number)
                        .frame(width: 60)
                        .onChange(of: self.settings.pollInterval) { _, newValue in
                            if newValue < 5 { self.settings.pollInterval = 5 }
                        }
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
            }

            Section("CLI Binary") {
                HStack {
                    Text("Path:")
                    Text(self.settings.resolvedCLIPath() ?? "Not found")
                        .foregroundStyle(self.settings.resolvedCLIPath() != nil ? Color.primary : Color.red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("Status:")
                    Text(cliStatus)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(self.settings.resolvedCLIPath() != nil ? "Reinstall from GitHub" : "Install from GitHub") {
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
