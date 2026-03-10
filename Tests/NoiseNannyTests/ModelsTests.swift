import Foundation
import Testing
@testable import NoiseNanny

// MARK: - Schedule Rule Logic

@Suite("Schedule Rule Logic")
struct ScheduleRuleTests {
    @Test("Disabled rule is never active")
    func disabledRuleIsNeverActive() {
        var rule = VolumeRule()
        rule.enabled = false

        #expect(!rule.isActiveNow())
    }

    @Test("Equal start and end produces inactive rule")
    func equalStartAndEndIsInactive() {
        let rule = VolumeRule(
            speakerName: "",
            maxVolume: 20,
            startHour: 10,
            startMinute: 0,
            endHour: 10,
            endMinute: 0,
            enabled: true
        )

        #expect(!rule.isActiveNow())
    }

    @Test("Rule is active for a window around now")
    func ruleActiveForWindowAroundNow() {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let current = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let start = (current + 1440 - 30) % 1440
        let end = (current + 30) % 1440

        let rule = VolumeRule(
            speakerName: "",
            maxVolume: 20,
            startHour: start / 60,
            startMinute: start % 60,
            endHour: end / 60,
            endMinute: end % 60,
            enabled: true
        )

        #expect(rule.isActiveNow())
    }

    @Test("Rule is inactive for a future window")
    func ruleInactiveForFutureWindow() {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let current = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let start = (current + 30) % 1440
        let end = (current + 90) % 1440

        let rule = VolumeRule(
            speakerName: "",
            maxVolume: 20,
            startHour: start / 60,
            startMinute: start % 60,
            endHour: end / 60,
            endMinute: end % 60,
            enabled: true
        )

        #expect(!rule.isActiveNow())
    }

    @Test("Time strings are zero-padded")
    func timeStringsFormatted() {
        let rule = VolumeRule(startHour: 7, startMinute: 5, endHour: 23, endMinute: 0)
        #expect(rule.startTimeString == "07:05")
        #expect(rule.endTimeString == "23:00")
    }

    @Test("Target label shows 'All Speakers' for empty name")
    func targetLabelEmpty() {
        let rule = VolumeRule(speakerName: "")
        #expect(rule.targetLabel == "All Speakers")
    }

    @Test("Target label shows speaker name when set")
    func targetLabelNamed() {
        let rule = VolumeRule(speakerName: "Kitchen")
        #expect(rule.targetLabel == "Kitchen")
    }
}

// MARK: - Speaker Targeting

@Suite("Speaker Targeting")
struct SpeakerTargetingTests {
    private let kitchen = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "speaker-kitchen")
    private let livingRoom = Speaker(ip: "1.2.3.5", name: "Living Room", udn: "speaker-living")
    private let office = Speaker(ip: "1.2.3.6", name: "Office", udn: "speaker-office")

    @Test("Empty target applies to all speakers")
    func appliesToAllSpeakersWhenTargetEmpty() {
        let rule = VolumeRule(speakerName: "")
        #expect(rule.appliesTo(kitchen))
    }

    @Test("Matching speaker name applies")
    func appliesToMatchingSpeakerName() {
        let rule = VolumeRule(speakerName: "Kitchen")
        #expect(rule.appliesTo(kitchen))
    }

    @Test("Non-matching speaker name does not apply")
    func doesNotApplyToWrongName() {
        let rule = VolumeRule(speakerName: "Kitchen")
        #expect(!rule.appliesTo(office))
    }

    @Test("Group targeting by group ID applies to all members")
    func appliesToGroupMemberByGroupId() {
        let group = SpeakerGroup(
            groupId: "group-1",
            coordinatorName: "Kitchen",
            members: [kitchen, livingRoom]
        )
        let rule = VolumeRule(
            speakerName: "\(VolumeRule.groupTargetPrefix)\(group.displayName)",
            targetGroupId: "group-1"
        )

        #expect(rule.appliesTo(kitchen, groups: [group]))
        #expect(rule.appliesTo(livingRoom, groups: [group]))
    }

    @Test("Group targeting does not apply to speakers outside the group")
    func doesNotApplyToSpeakerOutsideGroupById() {
        let group = SpeakerGroup(
            groupId: "group-1",
            coordinatorName: "Kitchen",
            members: [kitchen, livingRoom]
        )
        let rule = VolumeRule(
            speakerName: "\(VolumeRule.groupTargetPrefix)\(group.displayName)",
            targetGroupId: "group-1"
        )

        #expect(!rule.appliesTo(office, groups: [group]))
    }

    @Test("Legacy rules fall back to display name matching")
    func appliesToGroupMemberByDisplayNameFallback() {
        let group = SpeakerGroup(
            groupId: "group-1",
            coordinatorName: "Kitchen",
            members: [kitchen, livingRoom]
        )
        let rule = VolumeRule(speakerName: "\(VolumeRule.groupTargetPrefix)\(group.displayName)")

        #expect(rule.appliesTo(kitchen, groups: [group]))
    }

    @Test("AutoStopRule targeting works the same as VolumeRule")
    func autoStopRuleTargeting() {
        let rule = AutoStopRule(speakerName: "Kitchen")
        #expect(rule.appliesTo(kitchen))
        #expect(!rule.appliesTo(office))
    }
}

// MARK: - TransportState

@Suite("TransportState")
struct TransportStateTests {
    @Test("Parses PLAYING state")
    func parsesPlaying() {
        #expect(TransportState(raw: "PLAYING") == .playing)
        #expect(TransportState(raw: "PLAYING").isPlaying)
    }

    @Test("Parses PAUSED_PLAYBACK state")
    func parsesPaused() {
        #expect(TransportState(raw: "PAUSED_PLAYBACK") == .paused)
        #expect(!TransportState(raw: "PAUSED_PLAYBACK").isPlaying)
    }

    @Test("Parses STOPPED and empty as stopped")
    func parsesStopped() {
        #expect(TransportState(raw: "STOPPED") == .stopped)
        #expect(TransportState(raw: "") == .stopped)
    }

    @Test("Parses TRANSITIONING state")
    func parsesTransitioning() {
        #expect(TransportState(raw: "TRANSITIONING") == .transitioning)
    }

    @Test("Unknown strings produce .unknown")
    func parsesUnknown() {
        #expect(TransportState(raw: "SOMETHING_ELSE") == .unknown)
    }

    @Test("Parsing is case-insensitive")
    func caseInsensitive() {
        #expect(TransportState(raw: "playing") == .playing)
        #expect(TransportState(raw: "Paused_Playback") == .paused)
    }

    @Test("Accessibility label for each state")
    func accessibilityLabels() {
        #expect(TransportState.playing.accessibilityLabel == "Playing")
        #expect(TransportState.paused.accessibilityLabel == "Paused")
        #expect(TransportState.stopped.accessibilityLabel == "Stopped")
        #expect(TransportState.transitioning.accessibilityLabel == "Loading")
        #expect(TransportState.unknown.accessibilityLabel == "Stopped")
    }
}

// MARK: - StatusResponse Convenience

@Suite("StatusResponse Convenience")
struct StatusResponseTests {
    @Test("nowPlayingText formats artist and title")
    func nowPlayingFormatting() {
        let response = StatusResponse(
            device: nil,
            transport: nil,
            volume: 50,
            mute: false,
            nowPlaying: StatusResponse.NowPlaying(
                title: "Song",
                artist: "Artist",
                album: nil,
                itemClass: nil
            )
        )
        #expect(response.nowPlayingText == "Artist – Song")
    }

    @Test("nowPlayingText with only title")
    func nowPlayingTitleOnly() {
        let response = StatusResponse(
            device: nil,
            transport: nil,
            volume: nil,
            mute: nil,
            nowPlaying: StatusResponse.NowPlaying(
                title: "Podcast Episode",
                artist: nil,
                album: nil,
                itemClass: nil
            )
        )
        #expect(response.nowPlayingText == "Podcast Episode")
    }

    @Test("nowPlayingText with only artist")
    func nowPlayingArtistOnly() {
        let response = StatusResponse(
            device: nil,
            transport: nil,
            volume: nil,
            mute: nil,
            nowPlaying: StatusResponse.NowPlaying(
                title: nil,
                artist: "Radio Station",
                album: nil,
                itemClass: nil
            )
        )
        #expect(response.nowPlayingText == "Radio Station")
    }

    @Test("nowPlayingText returns empty when nil")
    func nowPlayingNil() {
        let response = StatusResponse(
            device: nil,
            transport: nil,
            volume: nil,
            mute: nil,
            nowPlaying: nil
        )
        #expect(response.nowPlayingText == "")
    }

    @Test("nowPlayingText skips empty strings")
    func nowPlayingEmptyStrings() {
        let response = StatusResponse(
            device: nil,
            transport: nil,
            volume: nil,
            mute: nil,
            nowPlaying: StatusResponse.NowPlaying(
                title: "",
                artist: "Artist",
                album: nil,
                itemClass: nil
            )
        )
        #expect(response.nowPlayingText == "Artist")
    }

    @Test("transportState parses from nested transport info")
    func transportStateParsing() {
        let response = StatusResponse(
            device: nil,
            transport: StatusResponse.TransportInfo(state: "PLAYING"),
            volume: nil,
            mute: nil,
            nowPlaying: nil
        )
        #expect(response.transportState == .playing)
    }

    @Test("transportState defaults to stopped when nil")
    func transportStateNil() {
        let response = StatusResponse(
            device: nil,
            transport: nil,
            volume: nil,
            mute: nil,
            nowPlaying: nil
        )
        #expect(response.transportState == .stopped)
    }
}

// MARK: - Speaker Group

@Suite("SpeakerGroup")
struct SpeakerGroupTests {
    private let kitchen = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "speaker-kitchen")
    private let livingRoom = Speaker(ip: "1.2.3.5", name: "Living Room", udn: "speaker-living")

    @Test("Single-member group uses coordinator name")
    func singleMemberDisplayName() {
        let group = SpeakerGroup(groupId: "g1", coordinatorName: "Kitchen", members: [kitchen])
        #expect(group.displayName == "Kitchen")
    }

    @Test("Multi-member group sorts and joins names")
    func multiMemberDisplayName() {
        let group = SpeakerGroup(
            groupId: "g1",
            coordinatorName: "Kitchen",
            members: [livingRoom, kitchen]
        )
        // Should be sorted: Kitchen + Living Room
        #expect(group.displayName == "Kitchen + Living Room")
    }
}

// MARK: - Speaker

@Suite("Speaker")
struct SpeakerTests {
    @Test("preservingState copies mutable fields from existing speaker")
    func preservingState() {
        var existing = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "udn-1")
        existing.volume = 42
        existing.mute = true
        existing.transportState = .playing
        existing.nowPlaying = "Artist – Song"

        let fresh = Speaker(ip: "1.2.3.99", name: "Kitchen", udn: "udn-1")
        let result = fresh.preservingState(from: existing)

        #expect(result.ip == "1.2.3.99")  // new IP
        #expect(result.volume == 42)
        #expect(result.mute == true)
        #expect(result.transportState == .playing)
        #expect(result.nowPlaying == "Artist – Song")
    }

    @Test("Equality is by UDN only, ignoring mutable state")
    func equalityByUdn() {
        var a = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "udn-1")
        a.volume = 10
        var b = Speaker(ip: "9.9.9.9", name: "Kitchen (renamed)", udn: "udn-1")
        b.volume = 99

        #expect(a == b)
    }

    @Test("Different UDNs are not equal")
    func inequalityByUdn() {
        let a = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "udn-1")
        let b = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "udn-2")

        #expect(a != b)
    }
}

// MARK: - Codable Round-trips

@Suite("Codable Round-trips")
struct CodableTests {
    @Test("VolumeRule survives encode/decode cycle")
    func volumeRuleCodable() throws {
        let rule = VolumeRule(
            speakerName: "Kitchen",
            targetGroupId: "g-1",
            maxVolume: 30,
            startHour: 22,
            startMinute: 15,
            endHour: 7,
            endMinute: 30,
            enabled: false
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(VolumeRule.self, from: data)

        #expect(decoded == rule)
    }

    @Test("AutoStopRule survives encode/decode cycle")
    func autoStopRuleCodable() throws {
        let rule = AutoStopRule(
            speakerName: "Office",
            targetGroupId: nil,
            startHour: 23,
            startMinute: 0,
            endHour: 6,
            endMinute: 0,
            enabled: true
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(AutoStopRule.self, from: data)

        #expect(decoded == rule)
    }

    @Test("Speaker encodes only identity fields (ip, name, udn)")
    func speakerCodableKeys() throws {
        var speaker = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "udn-1")
        speaker.volume = 99
        speaker.mute = true
        speaker.transportState = .playing

        let data = try JSONEncoder().encode(speaker)
        let json = try JSONDecoder().decode([String: String].self, from: data)

        #expect(json.keys.sorted() == ["ip", "name", "udn"])
    }
}

// MARK: - Version Parsing

@Suite("Semantic Version Extraction")
struct VersionParsingTests {
    @Test("Extracts version from 'sonos 0.1.0'")
    func extractFromBinaryOutput() {
        #expect(CLIInstaller.extractSemanticVersion("sonos 0.1.0") == "0.1.0")
    }

    @Test("Extracts version from 'v0.1.0' tag name")
    func extractFromTag() {
        #expect(CLIInstaller.extractSemanticVersion("v0.1.0") == "0.1.0")
    }

    @Test("Returns bare version as-is")
    func bareVersion() {
        #expect(CLIInstaller.extractSemanticVersion("1.2.3") == "1.2.3")
    }

    @Test("Trims whitespace and newlines")
    func trimsWhitespace() {
        #expect(CLIInstaller.extractSemanticVersion("  v2.0.0\n") == "2.0.0")
    }

    @Test("Returns trimmed input when no semver found")
    func noSemver() {
        #expect(CLIInstaller.extractSemanticVersion("unknown") == "unknown")
    }

    @Test("Handles empty string")
    func emptyString() {
        #expect(CLIInstaller.extractSemanticVersion("") == "")
    }
}
