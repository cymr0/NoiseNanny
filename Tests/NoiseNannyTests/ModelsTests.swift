import XCTest
@testable import NoiseNanny

final class ModelsTests: XCTestCase {
    func testDisabledRuleIsNeverActive() {
        var rule = VolumeRule()
        rule.enabled = false

        XCTAssertFalse(rule.isActiveNow())
    }

    func testEqualStartAndEndIsInactive() {
        let rule = VolumeRule(
            speakerName: "",
            maxVolume: 20,
            startHour: 10,
            startMinute: 0,
            endHour: 10,
            endMinute: 0,
            enabled: true
        )

        XCTAssertFalse(rule.isActiveNow())
    }

    func testRuleActiveForWindowAroundNow() {
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

        XCTAssertTrue(rule.isActiveNow())
    }

    func testRuleInactiveForFutureWindow() {
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

        XCTAssertFalse(rule.isActiveNow())
    }

    func testAppliesToAllSpeakersWhenTargetEmpty() {
        let rule = VolumeRule(speakerName: "")
        let speaker = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "speaker-kitchen")

        XCTAssertTrue(rule.appliesTo(speaker))
    }

    func testAppliesToMatchingSpeakerName() {
        let rule = VolumeRule(speakerName: "Kitchen")
        let speaker = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "speaker-kitchen")

        XCTAssertTrue(rule.appliesTo(speaker))
    }

    func testAppliesToGroupMemberByGroupId() {
        let kitchen = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "speaker-kitchen")
        let livingRoom = Speaker(ip: "1.2.3.5", name: "Living Room", udn: "speaker-living")
        let group = SpeakerGroup(
            groupId: "group-1",
            coordinatorName: "Kitchen",
            members: [kitchen, livingRoom]
        )
        let rule = VolumeRule(
            speakerName: "\(groupTargetPrefix)\(group.displayName)",
            targetGroupId: "group-1"
        )

        XCTAssertTrue(rule.appliesTo(kitchen, groups: [group]))
        XCTAssertTrue(rule.appliesTo(livingRoom, groups: [group]))
    }

    func testDoesNotApplyToSpeakerOutsideGroupById() {
        let kitchen = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "speaker-kitchen")
        let livingRoom = Speaker(ip: "1.2.3.5", name: "Living Room", udn: "speaker-living")
        let office = Speaker(ip: "1.2.3.6", name: "Office", udn: "speaker-office")
        let group = SpeakerGroup(
            groupId: "group-1",
            coordinatorName: "Kitchen",
            members: [kitchen, livingRoom]
        )
        let rule = VolumeRule(
            speakerName: "\(groupTargetPrefix)\(group.displayName)",
            targetGroupId: "group-1"
        )

        XCTAssertFalse(rule.appliesTo(office, groups: [group]))
    }

    func testAppliesToGroupMemberByDisplayNameFallback() {
        let kitchen = Speaker(ip: "1.2.3.4", name: "Kitchen", udn: "speaker-kitchen")
        let livingRoom = Speaker(ip: "1.2.3.5", name: "Living Room", udn: "speaker-living")
        let group = SpeakerGroup(
            groupId: "group-1",
            coordinatorName: "Kitchen",
            members: [kitchen, livingRoom]
        )
        // Legacy rule without targetGroupId — falls back to display name matching
        let rule = VolumeRule(speakerName: "\(groupTargetPrefix)\(group.displayName)")

        XCTAssertTrue(rule.appliesTo(kitchen, groups: [group]))
    }
}
