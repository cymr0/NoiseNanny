import Foundation
import Observation
import os

@Observable
final class SettingsStore {
    private static let logger = Logger(subsystem: "com.noisenanny.app", category: "SettingsStore")
    static let shared = SettingsStore()

    private enum Keys {
        static let volumeRules = "volumeRules"
        static let autoStopRules = "autoStopRules"
        static let pollInterval = "pollInterval"
        static let cliPath = "cliPath"
    }

    var volumeRules: [VolumeRule] {
        didSet { save(volumeRules, forKey: Keys.volumeRules) }
    }

    var autoStopRules: [AutoStopRule] {
        didSet { save(autoStopRules, forKey: Keys.autoStopRules) }
    }

    var pollInterval: TimeInterval {
        didSet { UserDefaults.standard.set(pollInterval, forKey: Keys.pollInterval) }
    }

    var cliPath: String {
        didSet { UserDefaults.standard.set(cliPath, forKey: Keys.cliPath) }
    }

    private init() {
        let interval = UserDefaults.standard.double(forKey: Keys.pollInterval)
        self.pollInterval = interval >= 5 ? interval : 30
        self.cliPath = UserDefaults.standard.string(forKey: Keys.cliPath) ?? ""
        self.volumeRules = Self.load(forKey: Keys.volumeRules) ?? []
        self.autoStopRules = Self.load(forKey: Keys.autoStopRules) ?? []
    }

    // MARK: - Persistence helpers

    private static func load<T: Decodable>(forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            Self.logger.error("Failed to save \(key): \(error.localizedDescription)")
        }
    }

    // MARK: - CLI path resolution

    func resolvedCLIPath() -> String? {
        let candidates = [
            cliPath,
            "/opt/homebrew/bin/sonos",
            "/usr/local/bin/sonos",
            appSupportBinaryPath()
        ]
        for path in candidates where !path.isEmpty {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                  !isDir.boolValue,
                  FileManager.default.isExecutableFile(atPath: path) else { continue }
            return path
        }
        return nil
    }

    func appSupportBinaryPath() -> String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return ""
        }
        return appSupport.appendingPathComponent("NoiseNanny/bin/sonos").path
    }
}
