import Testing
@testable import NoiseNanny

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
}

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
}

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
}

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
}
