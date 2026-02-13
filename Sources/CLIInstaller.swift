import Foundation

/// Downloads and updates the sonoscli binary from GitHub releases.
actor CLIInstaller {
    static let shared = CLIInstaller()

    private let repoOwner = "steipete"
    private let repoName = "sonoscli"
    private let binaryName = "sonos"

    struct ReleaseInfo: Sendable {
        let tagName: String
        let downloadURL: URL
    }

    enum InstallerError: LocalizedError {
        case noRelease
        case extractionFailed

        var errorDescription: String? {
            switch self {
            case .noRelease: return "No compatible release found on GitHub."
            case .extractionFailed: return "Failed to extract the CLI binary."
            }
        }
    }

    // MARK: - Process helper

    /// Waits for a process to exit without blocking the cooperative thread pool.
    /// Returns true if the process timed out.
    private func waitForExit(_ process: Process, timeout: TimeInterval = 30) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().async {
                        process.waitUntilExit()
                        continuation.resume()
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return true
            }
            let first = await group.next()!
            group.cancelAll()
            return first
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
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else {
            throw InstallerError.noRelease
        }

        // Find matching asset for current architecture
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "amd64"
        #else
        let arch = "unknown"
        #endif
        let assetName = assets.first {
            let name = ($0["name"] as? String) ?? ""
            return name.contains("darwin") && name.contains(arch)
        }

        guard let asset = assetName,
              let urlString = asset["browser_download_url"] as? String,
              let downloadURL = URL(string: urlString) else {
            throw InstallerError.noRelease
        }

        return ReleaseInfo(tagName: tagName, downloadURL: downloadURL)
    }

    // MARK: - Install

    func install() async throws -> String {
        let release = try await latestRelease()
        let destDir = try installDirectory()

        // Download
        let (tempURL, _) = try await URLSession.shared.download(from: release.downloadURL)

        // Create destination directory
        try FileManager.default.createDirectory(
            atPath: destDir,
            withIntermediateDirectories: true
        )

        // Extract tar.gz
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", tempURL.path, "-C", extractDir.path]
        try process.run()
        let extractTimedOut = await waitForExit(process, timeout: 30)
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
        var sourceFile: URL?
        if let enumerator = FileManager.default.enumerator(
            at: extractDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.lastPathComponent == binaryName {
                    sourceFile = fileURL
                    break
                }
            }
        }

        guard let source = sourceFile else {
            throw InstallerError.extractionFailed
        }

        // Replace existing
        if FileManager.default.fileExists(atPath: destPath) {
            try FileManager.default.removeItem(atPath: destPath)
        }
        try FileManager.default.moveItem(atPath: source.path, toPath: destPath)

        // Ensure executable
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destPath
        )

        // Cleanup
        do { try FileManager.default.removeItem(at: tempURL) }
        catch { print("NoiseNanny: Failed to clean up temp download: \(error.localizedDescription)") }
        do { try FileManager.default.removeItem(at: extractDir) }
        catch { print("NoiseNanny: Failed to clean up extraction dir: \(error.localizedDescription)") }

        // Update settings
        SettingsStore.shared.cliPath = destPath

        return release.tagName
    }

    func installDirectory() throws -> String {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw InstallerError.extractionFailed
        }
        return appSupport.appendingPathComponent("NoiseNanny/bin").path
    }

    func installedVersion() async -> String? {
        guard let path = SettingsStore.shared.resolvedCLIPath() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let timedOut = await waitForExit(process, timeout: 5)
            if timedOut { process.terminate(); return nil }
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
