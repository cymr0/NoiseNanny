import Testing
@testable import NoiseNanny

// MARK: - Version Comparison

@Suite("AppUpdateChecker.isNewer")
struct IsNewerTests {
    @Test("Newer major version")
    func newerMajorVersion() {
        #expect(AppUpdateChecker.isNewer(remote: "2.0.0", local: "1.0.0"))
    }

    @Test("Newer minor version")
    func newerMinorVersion() {
        #expect(AppUpdateChecker.isNewer(remote: "1.1.0", local: "1.0.0"))
    }

    @Test("Newer patch version")
    func newerPatchVersion() {
        #expect(AppUpdateChecker.isNewer(remote: "1.0.1", local: "1.0.0"))
    }

    @Test("Older major version")
    func olderMajorVersion() {
        #expect(!AppUpdateChecker.isNewer(remote: "1.0.0", local: "2.0.0"))
    }

    @Test("Older minor version")
    func olderMinorVersion() {
        #expect(!AppUpdateChecker.isNewer(remote: "1.0.0", local: "1.1.0"))
    }

    @Test("Older patch version")
    func olderPatchVersion() {
        #expect(!AppUpdateChecker.isNewer(remote: "1.0.0", local: "1.0.1"))
    }

    @Test("Equal versions")
    func equalVersions() {
        #expect(!AppUpdateChecker.isNewer(remote: "1.2.3", local: "1.2.3"))
    }

    @Test("Different component counts")
    func differentComponentCounts() {
        // remote has more components — trailing .1 makes it newer
        #expect(AppUpdateChecker.isNewer(remote: "1.0.0.1", local: "1.0.0"))
        // local has more components
        #expect(!AppUpdateChecker.isNewer(remote: "1.0.0", local: "1.0.0.1"))
    }

    @Test("Two-component versions")
    func twoComponentVersions() {
        #expect(AppUpdateChecker.isNewer(remote: "1.1", local: "1.0"))
        #expect(!AppUpdateChecker.isNewer(remote: "1.0", local: "1.1"))
        #expect(!AppUpdateChecker.isNewer(remote: "1.0", local: "1.0"))
    }

    @Test("Mixed component counts")
    func mixedComponentCounts() {
        // "1.1" vs "1.0.9" — 1.1.0 > 1.0.9
        #expect(AppUpdateChecker.isNewer(remote: "1.1", local: "1.0.9"))
        // "1.0" vs "1.0.1" — 1.0.0 < 1.0.1
        #expect(!AppUpdateChecker.isNewer(remote: "1.0", local: "1.0.1"))
    }
}

// MARK: - Semantic Version Extraction (via CLIInstaller)

@Suite("AppUpdateChecker version extraction")
struct VersionExtractionTests {
    @Test("Extracts version from tag with leading v")
    func extractsFromTag() {
        #expect(CLIInstaller.extractSemanticVersion("v1.2.3") == "1.2.3")
    }

    @Test("Extracts version from bare tag")
    func extractsFromBareTag() {
        #expect(CLIInstaller.extractSemanticVersion("1.2.3") == "1.2.3")
    }

    @Test("Extracts version from tool output")
    func extractsFromToolOutput() {
        #expect(CLIInstaller.extractSemanticVersion("sonos 0.1.0") == "0.1.0")
    }

    @Test("Extracts version with whitespace")
    func extractsWithWhitespace() {
        #expect(CLIInstaller.extractSemanticVersion("  v2.0.1\n") == "2.0.1")
    }

    @Test("Extracts version with prerelease suffix")
    func extractsWithPrerelease() {
        // The regex matches the first x.y.z; prerelease suffix is stripped
        #expect(CLIInstaller.extractSemanticVersion("v1.2.3-beta.1") == "1.2.3")
    }

    @Test("Non-semantic version returns raw trimmed")
    func nonSemanticVersion() {
        // No x.y.z match — returns the trimmed input as-is
        #expect(CLIInstaller.extractSemanticVersion("latest") == "latest")
    }
}

// MARK: - Download URL Extraction

@Suite("AppUpdateChecker.downloadURL")
struct DownloadURLTests {
    @Test("Finds NoiseNanny.zip asset")
    func findsNoiseNannyZip() {
        let assets: [[String: Any]] = [
            ["name": "sonoscli-darwin-arm64.tar.gz", "browser_download_url": "https://example.com/cli.tar.gz"],
            ["name": "NoiseNanny.zip", "browser_download_url": "https://example.com/NoiseNanny.zip"],
        ]
        let url = AppUpdateChecker.downloadURL(fromAssets: assets)
        #expect(url?.absoluteString == "https://example.com/NoiseNanny.zip")
    }

    @Test("Returns nil when asset missing")
    func returnsNilWhenMissing() {
        let assets: [[String: Any]] = [
            ["name": "sonoscli-darwin-arm64.tar.gz", "browser_download_url": "https://example.com/cli.tar.gz"],
        ]
        #expect(AppUpdateChecker.downloadURL(fromAssets: assets) == nil)
    }

    @Test("Returns nil for nil assets")
    func returnsNilForNil() {
        #expect(AppUpdateChecker.downloadURL(fromAssets: nil) == nil)
    }

    @Test("Returns nil for empty assets")
    func returnsNilForEmpty() {
        #expect(AppUpdateChecker.downloadURL(fromAssets: []) == nil)
    }

    @Test("Returns nil for invalid URL")
    func returnsNilForInvalidURL() {
        let assets: [[String: Any]] = [
            ["name": "NoiseNanny.zip", "browser_download_url": ""],
        ]
        // Empty string produces nil URL
        #expect(AppUpdateChecker.downloadURL(fromAssets: assets) == nil)
    }

    @Test("Ignores similarly named assets")
    func ignoresSimilarlyNamed() {
        let assets: [[String: Any]] = [
            ["name": "NoiseNanny.zip.sha256", "browser_download_url": "https://example.com/sha"],
            ["name": "NoiseNanny-debug.zip", "browser_download_url": "https://example.com/debug"],
        ]
        #expect(AppUpdateChecker.downloadURL(fromAssets: assets) == nil)
    }
}
