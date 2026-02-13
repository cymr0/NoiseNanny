import Foundation

/// Downloads and updates the sonoscli binary from GitHub releases.
actor CLIInstaller {
    static let shared = CLIInstaller()

    private let repoOwner = "steipete"
    private let repoName = "sonoscli"
    private let binaryName = "sonos"

    // MARK: - Types

    struct ReleaseInfo: Sendable {
        let tagName: String
        let downloadURL: URL
    }

    enum InstallerError: LocalizedError {
        case noRelease
        case extractionFailed
        case noAppSupportDirectory

        var errorDescription: String? {
            switch self {
            case .noRelease: return "No compatible release found on GitHub."
            case .extractionFailed: return "Failed to extract the CLI binary."
            case .noAppSupportDirectory: return "Could not locate Application Support directory."
            }
        }
    }

    /// Codable model for the GitHub Releases API response (replaces manual JSONSerialization).
    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    // MARK: - Version parsing

    /// Extracts the semver portion (e.g. "0.1.0") from strings like "sonos 0.1.0" or "v0.1.0".
    static func extractSemanticVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
            return String(trimmed[range])
        }
        return trimmed
    }

    // MARK: - Check latest release

    func latestRelease() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "amd64"
        #else
        let arch = "unknown"
        #endif

        guard let asset = release.assets.first(where: { $0.name.contains("darwin") && $0.name.contains(arch) }) else {
            throw InstallerError.noRelease
        }

        return ReleaseInfo(tagName: release.tagName, downloadURL: asset.browserDownloadUrl)
    }

    // MARK: - Install

    func install() async throws -> String {
        let release = try await latestRelease()
        let destDir = try installDirectory()

        // Download
        let (tempURL, _) = try await URLSession.shared.download(from: release.downloadURL)

        // Create destination directory
        try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        // Extract tar.gz
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", tempURL.path, "-C", extractDir.path]
        try process.run()

        let extractTimedOut = await ProcessRunner.runAndWait(process, timeout: 30)
        if extractTimedOut {
            process.terminate()
            throw InstallerError.extractionFailed
        }
        guard process.terminationStatus == 0 else {
            throw InstallerError.extractionFailed
        }

        // Find the binary in extracted files — search recursively since tarballs
        // may nest the binary inside a subdirectory.
        let destPath = destDir + "/\(binaryName)"
        let sourceFile = findBinary(named: binaryName, in: extractDir)
        guard let source = sourceFile else {
            throw InstallerError.extractionFailed
        }

        // Replace existing
        if FileManager.default.fileExists(atPath: destPath) {
            try FileManager.default.removeItem(atPath: destPath)
        }
        try FileManager.default.moveItem(atPath: source.path, toPath: destPath)

        // Ensure executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)

        // Cleanup temp files (best-effort)
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: extractDir)

        // Update settings
        SettingsStore.shared.cliPath = destPath

        return release.tagName
    }

    // MARK: - Helpers

    func installDirectory() throws -> String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw InstallerError.noAppSupportDirectory
        }
        return appSupport.appendingPathComponent("NoiseNanny/bin").path
    }

    func installedVersion() async -> String? {
        guard let path = SettingsStore.shared.resolvedCLIPath() else { return nil }
        do {
            let data = try await ProcessRunner.run(path, arguments: ["--version"], timeout: 5)
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func findBinary(named name: String, in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.lastPathComponent == name {
                return fileURL
            }
        }
        return nil
    }
}
