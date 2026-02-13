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

    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let time: Date
        let message: String
    }

    private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
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

    // MARK: - Speaker Discovery

    func refreshSpeakers() async {
        do {
            let groupResp = try await cli.groupStatus()
            applyGroupDiscovery(groupResp)
        } catch {
            // Fallback to plain discover if group status fails
            do {
                let discovered = try await cli.discover()
                applyFlatDiscovery(discovered)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func applyGroupDiscovery(_ response: GroupStatusResponse) {
        var allSpeakers: [Speaker] = []
        var newGroups: [SpeakerGroup] = []

        for g in response.groups {
            let members: [Speaker] = g.members.map { m in
                var speaker = Speaker(ip: m.ip, name: m.name, udn: m.uuid)
                if let existing = speakers.first(where: { $0.udn == m.uuid }) {
                    speaker = speaker.preservingState(from: existing)
                }
                return speaker
            }
            allSpeakers.append(contentsOf: members)
            newGroups.append(SpeakerGroup(
                groupId: g.id,
                coordinatorName: g.coordinator.name,
                members: members
            ))
        }

        speakers = allSpeakers
        groups = newGroups
        lastError = nil
    }

    private func applyFlatDiscovery(_ discovered: [Speaker]) {
        speakers = discovered.map { s in
            if let existing = speakers.first(where: { $0.udn == s.udn }) {
                return s.preservingState(from: existing)
            }
            return s
        }
        groups = speakers.map {
            SpeakerGroup(groupId: $0.udn, coordinatorName: $0.name, members: [$0])
        }
        lastError = nil
    }

    // MARK: - Poll & Enforce

    func pollAndEnforce() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        await refreshSpeakerStatuses()
        syncGroupMembers()
        lastPollTime = Date()

        await enforceVolumeCaps()
        await enforceAutoStop()
    }

    private func refreshSpeakerStatuses() async {
        let snapshot = speakers
        var results: [(String, StatusResponse)] = []
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
                case .success(let st): results.append((udn, st))
                case .failure(let error):
                    failCount += 1
                    lastFailError = error.localizedDescription
                }
            }
        }

        // Apply updates by UDN
        for (udn, st) in results {
            guard let i = speakers.firstIndex(where: { $0.udn == udn }) else { continue }
            speakers[i].volume = st.volume ?? speakers[i].volume
            speakers[i].mute = st.mute ?? speakers[i].mute
            speakers[i].transportState = st.transportState
            speakers[i].nowPlaying = st.nowPlayingText
        }

        if !speakers.isEmpty && failCount == speakers.count {
            lastError = "All speakers unreachable: \(lastFailError ?? "unknown error")"
        } else {
            lastError = nil
        }
    }

    private func syncGroupMembers() {
        for gi in groups.indices {
            for mi in groups[gi].members.indices {
                let udn = groups[gi].members[mi].udn
                if let speaker = speakers.first(where: { $0.udn == udn }) {
                    groups[gi].members[mi] = speaker
                }
            }
        }
    }

    private func enforceVolumeCaps() async {
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
    }

    private func enforceAutoStop() async {
        for rule in settings.autoStopRules where rule.isActiveNow() {
            for speaker in speakers where rule.appliesTo(speaker, groups: groups) {
                if speaker.transportState.isPlaying {
                    do {
                        try await cli.stop(speakerName: speaker.name)
                        if let idx = speakers.firstIndex(where: { $0.udn == speaker.udn }) {
                            speakers[idx].transportState = .stopped
                        }
                        log("Auto-stopped \(speaker.name) (quiet \(rule.startTimeString)–\(rule.endTimeString))")
                    } catch {
                        log("Failed to stop \(speaker.name): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        let entry = LogEntry(time: Date(), message: message)
        enforcementLog.insert(entry, at: 0)
        if enforcementLog.count > Self.maxLogEntries {
            enforcementLog.removeLast()
        }
    }

    // MARK: - UI Helpers

    func nextAutoStopTime() -> String? {
        let cal = Calendar.current
        let now = Date()
        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)

        if let active = settings.autoStopRules.first(where: { $0.isActiveNow() }) {
            return "Quiet until \(active.endTimeString)"
        }

        let upcoming = settings.autoStopRules
            .filter { $0.enabled }
            .map { ($0, $0.startHour * 60 + $0.startMinute) }
            .sorted { $0.1 < $1.1 }

        if let next = upcoming.first(where: { $0.1 > currentMinutes }) {
            return "Quiet at \(next.0.startTimeString)"
        }
        if let first = upcoming.first {
            return "Quiet at \(first.0.startTimeString) (tomorrow)"
        }
        return nil
    }

    func activeRuleCount() -> Int {
        settings.volumeRules.filter { $0.isActiveNow() }.count +
        settings.autoStopRules.filter { $0.isActiveNow() }.count
    }

    var allTargets: [RuleTarget] {
        var seen = Set<String>()
        var targets: [RuleTarget] = []
        for speaker in speakers {
            if seen.insert(speaker.name).inserted {
                targets.append(RuleTarget(speakerName: speaker.name, label: speaker.name, groupId: nil))
            }
        }
        for group in groups where group.members.count > 1 {
            let name = "\(VolumeRule.groupTargetPrefix)\(group.displayName)"
            if seen.insert(name).inserted {
                targets.append(RuleTarget(speakerName: name, label: name, groupId: group.groupId))
            }
        }
        return targets
    }
}
