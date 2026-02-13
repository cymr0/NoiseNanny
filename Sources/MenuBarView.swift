import SwiftUI

struct MenuBarView: View {
    @Environment(ScheduleEngine.self) private var engine
    @State private var settingsWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("NoiseNanny")
                    .font(.headline)
                Spacer()
                if engine.isPolling {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Speakers by group
            if engine.groups.isEmpty {
                Text("No speakers found")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(engine.groups) { group in
                    if group.members.count > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.3.group")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(group.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                    }
                    ForEach(group.members) { speaker in
                        SpeakerRow(speaker: speaker, indented: group.members.count > 1)
                    }
                }
            }

            Divider()

            // Active rules summary
            let activeCount = engine.activeRuleCount()
            if activeCount > 0 {
                Label(
                    "\(activeCount) rule\(activeCount == 1 ? "" : "s") active",
                    systemImage: "shield.checkered"
                )
                .foregroundStyle(.orange)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            if let nextStop = engine.nextAutoStopTime() {
                Label(nextStop, systemImage: "moon.fill")
                    .foregroundStyle(.purple)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            if let err = engine.lastError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            // Recent log
            if !engine.enforcementLog.isEmpty {
                Divider()
                Text("Recent Activity")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                ForEach(engine.enforcementLog.prefix(3)) { entry in
                    HStack(spacing: 4) {
                        Text(entry.time, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(entry.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 1)
                }
            }

            Divider()

            // Actions
            MenuActionRow(label: "Refresh Speakers", systemImage: "arrow.clockwise") {
                Task { await engine.refreshSpeakers() }
            }

            MenuActionRow(label: "Settings…", systemImage: "gear") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = settingsWindow {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    let settingsView = SettingsView()
                        .environment(engine)
                    let controller = NSHostingController(rootView: settingsView)
                    let window = NSWindow(contentViewController: controller)
                    window.title = "NoiseNanny Settings"
                    window.styleMask = [.titled, .closable, .resizable]
                    window.setContentSize(NSSize(width: 520, height: 560))
                    window.isReleasedWhenClosed = false
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                    settingsWindow = window
                }
            }

            Divider()

            MenuActionRow(label: "Quit NoiseNanny", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom, 4)
        }
        .frame(width: 300)
    }
}

// MARK: - Menu Action Row

private struct MenuActionRow: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
                .padding(.horizontal, 4)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Speaker Row

struct SpeakerRow: View {
    let speaker: Speaker
    var indented: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: speaker.transportState.icon)
                            .foregroundStyle(speaker.transportState.color)
                            .font(.caption)
                        Text(speaker.name)
                            .font(.system(.body, weight: .medium))
                    }
                    if !speaker.nowPlaying.isEmpty {
                        Text(speaker.nowPlaying)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(speaker.volume)%")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(volumeColor)
                    if speaker.mute {
                        Image(systemName: "speaker.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            // Volume bar
            GeometryReader { geo in
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(volumeColor)
                            .frame(width: geo.size.width * CGFloat(min(speaker.volume, 100)) / 100)
                    }
            }
            .frame(height: 3)
        }
        .padding(.leading, indented ? 24 : 12)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }

    private var volumeColor: Color {
        if speaker.volume > 80 { return .red }
        if speaker.volume > 50 { return .orange }
        return .primary
    }
}

// MARK: - TransportState UI

extension TransportState {
    var icon: String {
        switch self {
        case .playing: "play.fill"
        case .paused: "pause.fill"
        case .transitioning: "forward.fill"
        case .stopped, .unknown: "stop.fill"
        }
    }

    var color: Color {
        switch self {
        case .playing: .green
        case .paused: .orange
        case .transitioning: .blue
        case .stopped, .unknown: .secondary
        }
    }
}
