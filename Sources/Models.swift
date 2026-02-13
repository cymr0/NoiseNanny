import Foundation

// MARK: - Speaker

struct Speaker: Identifiable, Codable, Hashable {
    var id: String { udn }
    let ip: String
    let name: String
    let udn: String

    var volume: Int = 0
    var mute: Bool = false
    var transportState: String = ""
    var nowPlaying: String = ""

    enum CodingKeys: String, CodingKey {
        case ip, name, udn
    }

    // Hash/equality by stable identity only — mutable state (volume, mute, etc.)
    // must not affect identity in Sets or dictionary keys.
    static func == (lhs: Speaker, rhs: Speaker) -> Bool {
        lhs.udn == rhs.udn
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(udn)
    }
}

// MARK: - Group / Zone

struct SpeakerGroup: Identifiable {
    var id: String { groupId }
    let groupId: String
    let coordinatorName: String
    var members: [Speaker]

    var displayName: String {
        if members.count == 1 {
            return coordinatorName
        }
        // Sort member names so the display string is stable regardless of
        // the order Sonos returns members in.
        return members.map(\.name).sorted().joined(separator: " + ")
    }
}

// MARK: - Rule target (used by pickers in the settings UI)

struct RuleTarget: Identifiable {
    var id: String { speakerName }
    let speakerName: String   // value stored in rule.speakerName
    let label: String         // display text for the picker
    let groupId: String?      // non-nil for group targets
}

// MARK: - CLI JSON responses

struct DiscoverEntry: Decodable {
    let ip: String
    let name: String
    let udn: String
    let location: String?
}

struct GroupStatusResponse: Decodable {
    let groups: [GroupEntry]

    struct GroupEntry: Decodable {
        let id: String
        let coordinator: MemberEntry
        let members: [MemberEntry]
    }

    struct MemberEntry: Decodable {
        let name: String
        let ip: String
        let uuid: String
    }
}

struct StatusResponse: Decodable {
    let device: DeviceInfo?
    let transport: TransportInfo?
    let volume: Int?
    let mute: Bool?
    let nowPlaying: NowPlaying?

    struct DeviceInfo: Decodable {
        let ip: String?
        let name: String?
    }

    struct TransportInfo: Decodable {
        // Keys are capitalized in the actual JSON
        let state: String?

        enum CodingKeys: String, CodingKey {
            case state = "State"
        }
    }

    struct NowPlaying: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        // "class" field tells us the type (e.g. "object.item.audioItem.podcast")
        let itemClass: String?

        enum CodingKeys: String, CodingKey {
            case title, artist, album
            case itemClass = "class"
        }
    }
}

// MARK: - Rules

/// Prefix used to distinguish group targets from individual speaker names.
let groupTargetPrefix = "Group: "

/// Shared logic for time-window rules with speaker targeting.
protocol ScheduleRule {
    var speakerName: String { get }
    /// Stable Sonos group ID for group-targeted rules. Nil for individual speakers / "all".
    var targetGroupId: String? { get }
    var startHour: Int { get }
    var startMinute: Int { get }
    var endHour: Int { get }
    var endMinute: Int { get }
    var enabled: Bool { get }
}

extension ScheduleRule {
    var startTimeString: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var endTimeString: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    var targetLabel: String {
        speakerName.isEmpty ? "All Speakers" : speakerName
    }

    func isActiveNow() -> Bool {
        guard enabled else { return false }
        let cal = Calendar.current
        let now = Date()
        let currentMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        if startMinutes <= endMinutes {
            // Same-day window (e.g. 08:00–18:00)
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Overnight window (e.g. 22:00–07:00)
            return currentMinutes >= startMinutes || currentMinutes < endMinutes
        }
    }

    func appliesTo(_ speaker: Speaker, groups: [SpeakerGroup] = []) -> Bool {
        if speakerName.isEmpty { return true }
        if speakerName == speaker.name { return true }
        if speakerName.hasPrefix(groupTargetPrefix) {
            // Prefer stable group ID when available (new rules).
            if let gid = targetGroupId {
                return groups.contains { g in
                    g.groupId == gid && g.members.contains { $0.udn == speaker.udn }
                }
            }
            // Fallback: match by display name (legacy rules without targetGroupId).
            let groupDisplayName = String(speakerName.dropFirst(groupTargetPrefix.count))
            return groups.contains { g in
                g.displayName == groupDisplayName && g.members.contains { $0.udn == speaker.udn }
            }
        }
        return false
    }
}

struct VolumeRule: Identifiable, Codable, Equatable, ScheduleRule {
    let id: UUID
    var speakerName: String          // empty string = all speakers
    var targetGroupId: String?       // stable Sonos group ID (nil for individual / all)
    var maxVolume: Int               // 0–100
    var startHour: Int               // 0–23
    var startMinute: Int             // 0–59
    var endHour: Int                 // 0–23
    var endMinute: Int               // 0–59
    var enabled: Bool

    init(
        id: UUID = UUID(),
        speakerName: String = "",
        targetGroupId: String? = nil,
        maxVolume: Int = 20,
        startHour: Int = 22,
        startMinute: Int = 0,
        endHour: Int = 7,
        endMinute: Int = 0,
        enabled: Bool = true
    ) {
        self.id = id
        self.speakerName = speakerName
        self.targetGroupId = targetGroupId
        self.maxVolume = maxVolume
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.enabled = enabled
    }
}

struct AutoStopRule: Identifiable, Codable, Equatable, ScheduleRule {
    let id: UUID
    var speakerName: String          // empty = all speakers
    var targetGroupId: String?       // stable Sonos group ID (nil for individual / all)
    var startHour: Int               // 0–23
    var startMinute: Int             // 0–59
    var endHour: Int                 // 0–23
    var endMinute: Int               // 0–59
    var enabled: Bool

    init(
        id: UUID = UUID(),
        speakerName: String = "",
        targetGroupId: String? = nil,
        startHour: Int = 23,
        startMinute: Int = 0,
        endHour: Int = 7,
        endMinute: Int = 0,
        enabled: Bool = true
    ) {
        self.id = id
        self.speakerName = speakerName
        self.targetGroupId = targetGroupId
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.enabled = enabled
    }
}
