import Foundation

// MARK: - Transport State

/// Type-safe representation of Sonos transport states, replacing raw string comparisons.
enum TransportState: String, Sendable {
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case stopped = "STOPPED"
    case transitioning = "TRANSITIONING"
    case unknown

    /// Parse the state string returned by the CLI, which may vary in casing and format.
    init(raw: String) {
        let upper = raw.uppercased()
        if upper.contains("PLAY") && !upper.contains("PAUSE") {
            self = .playing
        } else if upper.contains("PAUSE") {
            self = .paused
        } else if upper.contains("TRANSIT") {
            self = .transitioning
        } else if upper.contains("STOP") || upper.isEmpty {
            self = .stopped
        } else {
            self = .unknown
        }
    }

    var isPlaying: Bool { self == .playing }
}

// MARK: - Speaker

struct Speaker: Identifiable, Codable, Hashable, Sendable {
    var id: String { udn }
    let ip: String
    let name: String
    let udn: String

    var volume: Int = 0
    var mute: Bool = false
    var transportState: TransportState = .stopped
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

    /// Returns a copy with mutable state preserved from an existing snapshot.
    func preservingState(from existing: Speaker) -> Speaker {
        var copy = self
        copy.volume = existing.volume
        copy.mute = existing.mute
        copy.transportState = existing.transportState
        copy.nowPlaying = existing.nowPlaying
        return copy
    }
}

// MARK: - Group / Zone

struct SpeakerGroup: Identifiable, Sendable {
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

struct RuleTarget: Identifiable, Sendable {
    var id: String { speakerName }
    let speakerName: String   // value stored in rule.speakerName
    let label: String         // display text for the picker
    let groupId: String?      // non-nil for group targets
}

// MARK: - CLI JSON responses

struct DiscoverEntry: Decodable, Sendable {
    let ip: String
    let name: String
    let udn: String
    let location: String?
}

struct GroupStatusResponse: Decodable, Sendable {
    let groups: [GroupEntry]

    struct GroupEntry: Decodable, Sendable {
        let id: String
        let coordinator: MemberEntry
        let members: [MemberEntry]
    }

    struct MemberEntry: Decodable, Sendable {
        let name: String
        let ip: String
        let uuid: String
    }
}

struct StatusResponse: Decodable, Sendable {
    let device: DeviceInfo?
    let transport: TransportInfo?
    let volume: Int?
    let mute: Bool?
    let nowPlaying: NowPlaying?

    struct DeviceInfo: Decodable, Sendable {
        let ip: String?
        let name: String?
    }

    struct TransportInfo: Decodable, Sendable {
        let state: String?

        enum CodingKeys: String, CodingKey {
            case state = "State"
        }
    }

    struct NowPlaying: Decodable, Sendable {
        let title: String?
        let artist: String?
        let album: String?
        let itemClass: String?

        enum CodingKeys: String, CodingKey {
            case title, artist, album
            case itemClass = "class"
        }
    }

    /// Convenience: parsed transport state.
    var transportState: TransportState {
        TransportState(raw: transport?.state ?? "")
    }

    /// Convenience: formatted "now playing" string.
    var nowPlayingText: String {
        guard let np = nowPlaying else { return "" }
        return [np.artist, np.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
    }
}

// MARK: - Rules

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
    /// Prefix used to distinguish group targets from individual speaker names.
    static var groupTargetPrefix: String { "Group: " }

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
        if speakerName.hasPrefix(Self.groupTargetPrefix) {
            // Prefer stable group ID when available (new rules).
            if let gid = targetGroupId {
                return groups.contains { g in
                    g.groupId == gid && g.members.contains { $0.udn == speaker.udn }
                }
            }
            // Fallback: match by display name (legacy rules without targetGroupId).
            let groupDisplayName = String(speakerName.dropFirst(Self.groupTargetPrefix.count))
            return groups.contains { g in
                g.displayName == groupDisplayName && g.members.contains { $0.udn == speaker.udn }
            }
        }
        return false
    }
}

struct VolumeRule: Identifiable, Codable, Equatable, ScheduleRule, Sendable {
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

struct AutoStopRule: Identifiable, Codable, Equatable, ScheduleRule, Sendable {
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
