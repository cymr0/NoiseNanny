import XCTest
@testable import NoiseNanny

final class AppUpdateCheckerTests: XCTestCase {

    // MARK: - isNewer(remote:local:)

    func testNewerMajorVersion() {
        XCTAssertTrue(AppUpdateChecker.isNewer(remote: "2.0.0", local: "1.0.0"))
    }

    func testNewerMinorVersion() {
        XCTAssertTrue(AppUpdateChecker.isNewer(remote: "1.1.0", local: "1.0.0"))
    }

    func testNewerPatchVersion() {
        XCTAssertTrue(AppUpdateChecker.isNewer(remote: "1.0.1", local: "1.0.0"))
    }

    func testOlderMajorVersion() {
        XCTAssertFalse(AppUpdateChecker.isNewer(remote: "1.0.0", local: "2.0.0"))
    }

    func testOlderMinorVersion() {
        XCTAssertFalse(AppUpdateChecker.isNewer(remote: "1.0.0", local: "1.1.0"))
    }

    func testOlderPatchVersion() {
        XCTAssertFalse(AppUpdateChecker.isNewer(remote: "1.0.0", local: "1.0.1"))
    }

    func testEqualVersions() {
        XCTAssertFalse(AppUpdateChecker.isNewer(remote: "1.2.3", local: "1.2.3"))
    }

    func testDifferentComponentCounts() {
        // remote has more components — trailing .1 makes it newer
        XCTAssertTrue(AppUpdateChecker.isNewer(remote: "1.0.0.1", local: "1.0.0"))
        // local has more components
        XCTAssertFalse(AppUpdateChecker.isNewer(remote: "1.0.0", local: "1.0.0.1"))
    }

    func testTwoComponentVersions() {
        XCTAssertTrue(AppUpdateChecker.isNewer(remote: "1.1", local: "1.0"))
        XCTAssertFalse(AppUpdateChecker.isNewer(remote: "1.0", local: "1.1"))
        XCTAssertFalse(AppUpdateChecker.isNewer(remote: "1.0", local: "1.0"))
    }

    func testMixedComponentCounts() {
        // "1.1" vs "1.0.9" — 1.1.0 > 1.0.9
        XCTAssertTrue(AppUpdateChecker.isNewer(remote: "1.1", local: "1.0.9"))
        // "1.0" vs "1.0.1" — 1.0.0 < 1.0.1
        XCTAssertFalse(AppUpdateChecker.isNewer(remote: "1.0", local: "1.0.1"))
    }

    // MARK: - extractSemanticVersion

    func testExtractsVersionFromTagWithLeadingV() {
        XCTAssertEqual(CLIInstaller.extractSemanticVersion("v1.2.3"), "1.2.3")
    }

    func testExtractsVersionFromBareTag() {
        XCTAssertEqual(CLIInstaller.extractSemanticVersion("1.2.3"), "1.2.3")
    }

    func testExtractsVersionFromToolOutput() {
        XCTAssertEqual(CLIInstaller.extractSemanticVersion("sonos 0.1.0"), "0.1.0")
    }

    func testExtractsVersionWithWhitespace() {
        XCTAssertEqual(CLIInstaller.extractSemanticVersion("  v2.0.1\n"), "2.0.1")
    }

    func testExtractsVersionWithPrereleaseSuffix() {
        // The regex matches the first x.y.z; prerelease suffix is stripped
        XCTAssertEqual(CLIInstaller.extractSemanticVersion("v1.2.3-beta.1"), "1.2.3")
    }

    func testNonSemanticVersionReturnsRawTrimmed() {
        // No x.y.z match — returns the trimmed input as-is
        XCTAssertEqual(CLIInstaller.extractSemanticVersion("latest"), "latest")
    }

    // MARK: - downloadURL(fromAssets:)

    func testDownloadURLFindsNoiseNannyZip() {
        let assets: [[String: Any]] = [
            ["name": "sonoscli-darwin-arm64.tar.gz", "browser_download_url": "https://example.com/cli.tar.gz"],
            ["name": "NoiseNanny.zip", "browser_download_url": "https://example.com/NoiseNanny.zip"],
        ]
        let url = AppUpdateChecker.downloadURL(fromAssets: assets)
        XCTAssertEqual(url?.absoluteString, "https://example.com/NoiseNanny.zip")
    }

    func testDownloadURLReturnsNilWhenAssetMissing() {
        let assets: [[String: Any]] = [
            ["name": "sonoscli-darwin-arm64.tar.gz", "browser_download_url": "https://example.com/cli.tar.gz"],
        ]
        XCTAssertNil(AppUpdateChecker.downloadURL(fromAssets: assets))
    }

    func testDownloadURLReturnsNilForNilAssets() {
        XCTAssertNil(AppUpdateChecker.downloadURL(fromAssets: nil))
    }

    func testDownloadURLReturnsNilForEmptyAssets() {
        XCTAssertNil(AppUpdateChecker.downloadURL(fromAssets: []))
    }

    func testDownloadURLReturnsNilForInvalidURL() {
        let assets: [[String: Any]] = [
            ["name": "NoiseNanny.zip", "browser_download_url": ""],
        ]
        // Empty string produces nil URL
        XCTAssertNil(AppUpdateChecker.downloadURL(fromAssets: assets))
    }

    func testDownloadURLIgnoresSimilarlyNamedAssets() {
        let assets: [[String: Any]] = [
            ["name": "NoiseNanny.zip.sha256", "browser_download_url": "https://example.com/sha"],
            ["name": "NoiseNanny-debug.zip", "browser_download_url": "https://example.com/debug"],
        ]
        XCTAssertNil(AppUpdateChecker.downloadURL(fromAssets: assets))
    }
}
