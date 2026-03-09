import AppKit
import Foundation

/// Checks for new NoiseNanny releases on GitHub.
actor AppUpdateChecker {
    static let shared = AppUpdateChecker()

    private let repoOwner = "cymr0"
    private let repoName = "NoiseNanny"

    struct UpdateInfo: Sendable {
        let tagName: String
        let htmlURL: String
        let downloadURL: URL?
    }

    enum UpdateError: LocalizedError {
        case httpError(statusCode: Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .httpError(let code):
                return "GitHub API returned HTTP \(code)"
            case .invalidResponse:
                return "Unexpected response format from GitHub"
            }
        }
    }

    /// Returns the current app version from the main bundle's CFBundleShortVersionString.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    /// Checks GitHub for a newer release. Returns `UpdateInfo` if one exists, nil if up to date.
    /// Throws on network or API errors so callers can distinguish failure from "no update".
    func checkForUpdate() async throws -> UpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw UpdateError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlURL = json["html_url"] as? String else {
            throw UpdateError.invalidResponse
        }

        let remoteVersion = CLIInstaller.extractSemanticVersion(tagName)
        let localVersion = CLIInstaller.extractSemanticVersion(currentVersion)

        guard !remoteVersion.isEmpty, remoteVersion != localVersion,
              Self.isNewer(remote: remoteVersion, local: localVersion) else {
            return nil
        }

        // Find the NoiseNanny.zip asset download URL
        var zipURL: URL?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let name = asset["name"] as? String, name == "NoiseNanny.zip",
                   let urlString = asset["browser_download_url"] as? String {
                    zipURL = URL(string: urlString)
                    break
                }
            }
        }

        return UpdateInfo(tagName: tagName, htmlURL: htmlURL, downloadURL: zipURL)
    }

    enum InstallError: LocalizedError {
        case noDownloadAsset
        case extractionFailed
        case appNotFound

        var errorDescription: String? {
            switch self {
            case .noDownloadAsset: return "No NoiseNanny.zip asset found in release."
            case .extractionFailed: return "Failed to extract the app update."
            case .appNotFound: return "NoiseNanny.app not found in archive."
            }
        }
    }

    /// Downloads and installs the app update, then relaunches.
    func installUpdate(_ update: UpdateInfo) async throws {
        guard let downloadURL = update.downloadURL else {
            throw InstallError.noDownloadAsset
        }

        let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // Unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", tempURL.path, "-d", extractDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw InstallError.extractionFailed
        }

        let extractedApp = extractDir.appendingPathComponent("NoiseNanny.app")
        guard FileManager.default.fileExists(atPath: extractedApp.path) else {
            throw InstallError.appNotFound
        }

        // Replace the running app bundle
        let currentAppURL = Bundle.main.bundleURL
        let parent = currentAppURL.deletingLastPathComponent()
        let backupURL = parent.appendingPathComponent("NoiseNanny.app.bak")

        // Remove any previous backup
        try? FileManager.default.removeItem(at: backupURL)
        // Back up current app
        try FileManager.default.moveItem(at: currentAppURL, to: backupURL)

        do {
            try FileManager.default.copyItem(at: extractedApp, to: currentAppURL)
        } catch {
            // Restore backup on failure
            try? FileManager.default.moveItem(at: backupURL, to: currentAppURL)
            throw error
        }

        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: extractDir)

        // Relaunch
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", currentAppURL.path]
        try? task.run()

        // Terminate current instance after a short delay to let the new one start
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApplication.shared.terminate(nil)
        }
    }

    /// Simple semver comparison: returns true if remote > local.
    static func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
