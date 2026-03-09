import Foundation

/// Checks for new NoiseNanny releases on GitHub.
actor AppUpdateChecker {
    static let shared = AppUpdateChecker()

    private let repoOwner = "cymr0"
    private let repoName = "NoiseNanny"

    struct UpdateInfo: Sendable {
        let tagName: String
        let htmlURL: String
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

        return UpdateInfo(tagName: tagName, htmlURL: htmlURL)
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
