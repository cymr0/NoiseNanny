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

    /// Extracts the `NoiseNanny.zip` download URL from a GitHub release JSON `assets` array.
    /// Extracted as a pure helper for testability.
    static func downloadURL(fromAssets assets: [[String: Any]]?) -> URL? {
        guard let assets else { return nil }
        for asset in assets {
            if let name = asset["name"] as? String, name == "NoiseNanny.zip",
               let urlString = asset["browser_download_url"] as? String {
                return URL(string: urlString)
            }
        }
        return nil
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

        let zipURL = Self.downloadURL(fromAssets: json["assets"] as? [[String: Any]])

        return UpdateInfo(tagName: tagName, htmlURL: htmlURL, downloadURL: zipURL)
    }

    enum InstallError: LocalizedError {
        case noDownloadAsset
        case downloadFailed(statusCode: Int)
        case extractionFailed
        case extractionTimedOut
        case appNotFound
        case replaceFailed(underlying: String)
        case relaunchFailed

        var errorDescription: String? {
            switch self {
            case .noDownloadAsset: return "No NoiseNanny.zip asset found in release."
            case .downloadFailed(let code): return "Download failed with HTTP \(code)."
            case .extractionFailed: return "Failed to extract the app update."
            case .extractionTimedOut: return "Extraction timed out."
            case .appNotFound: return "NoiseNanny.app not found in archive."
            case .replaceFailed(let detail):
                return "Failed to replace app bundle. Manual recovery may be needed — check for a .bak file in the app's parent directory. (\(detail))"
            case .relaunchFailed: return "Updated app could not be launched. Please open NoiseNanny manually."
            }
        }
    }

    /// Downloads and installs the app update, then relaunches.
    func installUpdate(_ update: UpdateInfo) async throws {
        guard let downloadURL = update.downloadURL else {
            throw InstallError.noDownloadAsset
        }

        // Download and validate HTTP response
        let (tempURL, downloadResponse) = try await URLSession.shared.download(from: downloadURL)
        if let httpResponse = downloadResponse as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: tempURL)
            throw InstallError.downloadFailed(statusCode: httpResponse.statusCode)
        }

        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // Ensure temp artifacts are cleaned up on all paths
        defer {
            if let err = Result(catching: { try FileManager.default.removeItem(at: tempURL) }).failure {
                print("NoiseNanny: Failed to clean up temp download: \(err.localizedDescription)")
            }
            if let err = Result(catching: { try FileManager.default.removeItem(at: extractDir) }).failure {
                print("NoiseNanny: Failed to clean up extraction dir: \(err.localizedDescription)")
            }
        }

        // Unzip using async-safe wait with timeout (same pattern as CLIInstaller)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", tempURL.path, "-d", extractDir.path]
        try process.run()

        let timedOut = await ProcessRunner.runAndWait(process, timeout: 30)
        if timedOut {
            process.terminate()
            throw InstallError.extractionTimedOut
        }

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
            // Attempt restore — if this also fails, throw a dedicated error with recovery instructions
            do {
                try FileManager.default.moveItem(at: backupURL, to: currentAppURL)
            } catch let restoreError {
                throw InstallError.replaceFailed(
                    underlying: "Copy failed: \(error.localizedDescription). "
                    + "Restore also failed: \(restoreError.localizedDescription). "
                    + "Backup is at: \(backupURL.path)"
                )
            }
            throw error
        }

        // Clean up backup after successful copy
        try? FileManager.default.removeItem(at: backupURL)

        // Relaunch — only terminate if the new app actually launches
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-n", currentAppURL.path]
        try launcher.run()
        launcher.waitUntilExit()

        guard launcher.terminationStatus == 0 else {
            throw InstallError.relaunchFailed
        }

        await MainActor.run {
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

private extension Result where Failure == any Error {
    var failure: Failure? {
        switch self {
        case .success: return nil
        case .failure(let err): return err
        }
    }
}
