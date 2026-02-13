import Foundation

/// Async wrapper around the sonos CLI binary.
actor SonosCLI {
    private let settings: SettingsStore

    init(settings: SettingsStore = .shared) {
        self.settings = settings
    }

    private func binaryPath() throws -> String {
        guard let path = settings.resolvedCLIPath() else {
            throw CLIError.binaryNotFound
        }
        return path
    }

    enum CLIError: LocalizedError {
        case binaryNotFound

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "sonos CLI binary not found. Check Settings or install via Homebrew."
            }
        }
    }

    // MARK: - Run

    private func run(_ arguments: [String], timeout: TimeInterval = 10) async throws -> Data {
        try await ProcessRunner.run(try binaryPath(), arguments: arguments, timeout: timeout)
    }

    // MARK: - Discover

    func discover() async throws -> [Speaker] {
        let data = try await run(["discover", "--format", "json"], timeout: 15)
        let entries = try JSONDecoder().decode([DiscoverEntry].self, from: data)
        return entries.map { Speaker(ip: $0.ip, name: $0.name, udn: $0.udn) }
    }

    // MARK: - Groups

    func groupStatus() async throws -> GroupStatusResponse {
        let data = try await run(["group", "status", "--all", "--format", "json"], timeout: 15)
        return try JSONDecoder().decode(GroupStatusResponse.self, from: data)
    }

    // MARK: - Status

    func status(speakerName: String) async throws -> StatusResponse {
        let data = try await run(["now", "--name", speakerName, "--format", "json"])
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    // MARK: - Volume

    func setVolume(speakerName: String, volume: Int) async throws {
        let clamped = max(0, min(100, volume))
        _ = try await run(["volume", "set", "--name", speakerName, "\(clamped)"])
    }

    // MARK: - Playback control

    func pause(speakerName: String) async throws {
        _ = try await run(["pause", "--name", speakerName])
    }

    func stop(speakerName: String) async throws {
        // Try pause first (more graceful), fall back to stop
        do {
            _ = try await run(["pause", "--name", speakerName])
        } catch let pauseError {
            do {
                _ = try await run(["stop", "--name", speakerName])
            } catch let stopError {
                throw ProcessRunnerError.nonZeroExit(
                    status: -1,
                    stderr: "Pause failed: \(pauseError.localizedDescription); Stop failed: \(stopError.localizedDescription)"
                )
            }
        }
    }
}
