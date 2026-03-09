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
}
