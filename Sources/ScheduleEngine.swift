import Foundation

/// Timer-based engine that polls speakers and enforces volume caps + auto-stop rules.
@Observable
@MainActor
final class ScheduleEngine {
    private static let maxLogEntries = 50

    let cli = SonosCLI()
    let settings = SettingsStore.shared

    var speakers: [Speaker] = []
    var groups: [SpeakerGroup] = []
    var lastPollTime: Date?
    var lastError: String?
    var isPolling = false
    var enforcementLog: [LogEntry] = []
    var availableUpdate: AppUpdateChecker.UpdateInfo?

    struct LogEntry: Identifiable {
        let id = UUID()
        let time: Date
        let message: String
    }

    private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            // Initial discover + immediate status fetch
            await refreshSpeakers()
            await pollAndEnforce()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(settings.pollInterval))
                await pollAndEnforce()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshSpeakers() async {
        do {
            // Prefer group status — gives us speakers and their grouping in one call.
            // Falls back to plain discover below if this fails (e.g. older CLI version).
            let groupResp = try await cli.groupStatus()
            var allSpeakers: [Speaker] = []
            var newGroups: [SpeakerGroup] = []

            for g in groupResp.groups {
                var members: [Speaker] = []
                for m in g.members {
                    var speaker = Speaker(ip: m.ip, name: m.name, udn: m.uuid)
                    // Preserve existing state if we already know this speaker
                    if let existing = speakers.first(where: { $0.udn == m.uuid }) {
                        speaker.volume = existing.volume
                        speaker.mute = existing.mute
                        speaker.transportState = existing.transportState
                        speaker.nowPlaying = existing.nowPlaying
                    }
                    members.append(speaker)
                    allSpeakers.append(speaker)
                }
                newGroups.append(SpeakerGroup(
                    groupId: g.id,
                    coordinatorName: g.coordinator.name,
                    members: members
                ))
            }

            speakers = allSpeakers
            groups = newGroups
            lastError = nil
        } catch {
            // Fallback to plain discover if group status fails
            do {
                let discovered = try await cli.discover()
                var updated: [Speaker] = []
                for var s in discovered {
                    if let existing = speakers.first(where: { $0.udn == s.udn }) {
                        s.volume = existing.volume
                        s.mute = existing.mute
                        s.transportState = existing.transportState
                        s.nowPlaying = existing.nowPlaying
                    }
                    updated.append(s)
                }
                speakers = updated
                // Single group per speaker as fallback
                groups = updated.map {
                    SpeakerGroup(groupId: $0.udn, coordinatorName: $0.name, members: [$0])
                }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func pollAndEnforce() async {
        // Prevent concurrent execution — protects the speakers array from data races.
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        // Refresh status for each speaker in parallel
        let snapshot = speakers
        var results: [(String, StatusResponse)] = []   // (udn, response)
        var failCount = 0
        var lastFailError: String?

        await withTaskGroup(of: (String, Result<StatusResponse, Error>).self) { group in
            for speaker in snapshot {
                group.addTask { [name = speaker.name, udn = speaker.udn] in
                    do {
                        let st = try await self.cli.status(speakerName: name)
                        return (udn, .success(st))
                    } catch {
                        return (udn, .failure(error))
                    }
                }
            }
            for await (udn, result) in group {
                switch result {
                case .success(let st):
                    results.append((udn, st))
                case .failure(let error):
                    failCount += 1
                    lastFailError = error.localizedDescription
                }
            }
        }

        // Apply updates by UDN (safe even if speakers array was modified concurrently)
        for (udn, st) in results {
            guard let i = speakers.firstIndex(where: { $0.udn == udn }) else { continue }
            speakers[i].volume = st.volume ?? speakers[i].volume
            speakers[i].mute = st.mute ?? speakers[i].mute
            speakers[i].transportState = st.transport?.state ?? ""
            if let np = st.nowPlaying {
                let parts = [np.artist, np.title].compactMap { $0 }.filter { !$0.isEmpty }
                speakers[i].nowPlaying = parts.joined(separator: " – ")
            } else {
                speakers[i].nowPlaying = ""
            }
        }

        // Surface error state
        if !speakers.isEmpty && failCount == speakers.count {
            lastError = "All speakers unreachable: \(lastFailError ?? "unknown error")"
        } else {
            lastError = nil
        }

        // Sync speaker state back into groups
        for gi in groups.indices {
            for mi in groups[gi].members.indices {
                let udn = groups[gi].members[mi].udn
                if let speaker = speakers.first(where: { $0.udn == udn }) {
                    groups[gi].members[mi] = speaker
                }
            }
        }

        lastPollTime = Date()

        // Enforce volume caps
        for rule in settings.volumeRules where rule.isActiveNow() {
            for speaker in speakers where rule.appliesTo(speaker, groups: groups) {
                if speaker.volume > rule.maxVolume {
                    do {
                        try await cli.setVolume(speakerName: speaker.name, volume: rule.maxVolume)
                        log("Clamped \(speaker.name) from \(speaker.volume)% → \(rule.maxVolume)%")
                    } catch {
                        log("Failed to clamp \(speaker.name): \(error.localizedDescription)")
                    }
                }
            }
        }

        // Auto-stop: enforce quiet window continuously while active
        for rule in settings.autoStopRules where rule.isActiveNow() {
            for speaker in speakers where rule.appliesTo(speaker, groups: groups) {
                let state = speaker.transportState.uppercased()
                let isPlaying = state.contains("PLAY") && !state.contains("PAUSE")
                if isPlaying {
                    do {
                        try await cli.stop(speakerName: speaker.name)
                        if let idx = speakers.firstIndex(where: { $0.udn == speaker.udn }) {
                            speakers[idx].transportState = "STOPPED"
                        }
                        log("Auto-stopped \(speaker.name) (quiet \(rule.startTimeString)–\(rule.endTimeString))")
                    } catch {
                        log("Failed to stop \(speaker.name): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func log(_ message: String) {
        let entry = LogEntry(time: Date(), message: message)
        enforcementLog.insert(entry, at: 0)
        if enforcementLog.count > Self.maxLogEntries {
            enforcementLog.removeLast()
        }
    }


    // MARK: - Helpers for UI

    func nextAutoStopTime() -> String? {
        let cal = Calendar.current
        let now = Date()
        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        // Check if any rule is currently active
        if let active = settings.autoStopRules.first(where: { $0.isActiveNow() }) {
            return "Quiet until \(active.endTimeString)"
        }

        // Find next upcoming start time today
        let upcoming = settings.autoStopRules
            .filter { $0.enabled }
            .map { ($0, $0.startHour * 60 + $0.startMinute) }
            .sorted { $0.1 < $1.1 }

        if let next = upcoming.first(where: { $0.1 > currentMinutes }) {
            return "Quiet at \(next.0.startTimeString)"
        }
        // Otherwise first one tomorrow
        if let first = upcoming.first {
            return "Quiet at \(first.0.startTimeString) (tomorrow)"
        }
        return nil
    }

    /// Count of all currently active rules (volume caps + auto-stop).
    func activeRuleCount() -> Int {
        settings.volumeRules.filter { $0.isActiveNow() }.count +
        settings.autoStopRules.filter { $0.isActiveNow() }.count
    }

    /// All unique targets for rule pickers: speaker names + group names (when > 1 member).
    var allTargets: [RuleTarget] {
        var seen = Set<String>()
        var targets: [RuleTarget] = []
        for speaker in speakers {
            if seen.insert(speaker.name).inserted {
                targets.append(RuleTarget(
                    speakerName: speaker.name,
                    label: speaker.name,
                    groupId: nil
                ))
            }
        }
        for group in groups where group.members.count > 1 {
            let name = "\(groupTargetPrefix)\(group.displayName)"
            if seen.insert(name).inserted {
                targets.append(RuleTarget(
                    speakerName: name,
                    label: name,
                    groupId: group.groupId
                ))
            }
        }
        return targets
    }
}
