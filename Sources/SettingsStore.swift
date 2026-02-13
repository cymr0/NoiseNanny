import Foundation
import SwiftUI

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private let rulesKey = "volumeRules"
    private let autoStopKey = "autoStopRules"
    private let pollIntervalKey = "pollInterval"
    private let cliPathKey = "cliPath"

    var volumeRules: [VolumeRule] {
        didSet { save(volumeRules, forKey: rulesKey) }
    }

    var autoStopRules: [AutoStopRule] {
        didSet { save(autoStopRules, forKey: autoStopKey) }
    }

    var pollInterval: TimeInterval {
        didSet { UserDefaults.standard.set(pollInterval, forKey: pollIntervalKey) }
    }

    var cliPath: String {
        didSet { UserDefaults.standard.set(cliPath, forKey: cliPathKey) }
    }

    private init() {
        // Must initialize all stored properties before using self
        let interval = UserDefaults.standard.double(forKey: pollIntervalKey)
        self.pollInterval = interval >= 5 ? interval : 30

        self.cliPath = UserDefaults.standard.string(forKey: cliPathKey) ?? ""

        if let data = UserDefaults.standard.data(forKey: rulesKey),
           let decoded = try? JSONDecoder().decode([VolumeRule].self, from: data) {
            self.volumeRules = decoded
        } else {
            self.volumeRules = []
        }

        if let data = UserDefaults.standard.data(forKey: autoStopKey),
           let decoded = try? JSONDecoder().decode([AutoStopRule].self, from: data) {
            self.autoStopRules = decoded
        } else {
            self.autoStopRules = []
        }
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("NoiseNanny: Failed to save \(key): \(error.localizedDescription)")
        }
    }

    /// Resolves the CLI binary path. Checks stored path, then common locations.
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
