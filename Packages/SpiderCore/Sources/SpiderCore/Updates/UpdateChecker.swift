import Foundation
import Observation
import OSLog

/// A version like "1.0" or "v1.2.3". "1.0" and "1.0.0" are the same version.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        // "1.2.3-beta" → "1.2.3"
        let numbers = text.prefix { $0.isNumber || $0 == "." }
        let parts = numbers.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

/// A newer release people can download.
public struct AvailableUpdate: Equatable, Sendable {
    public let version: AppVersion
    /// The release page on GitHub.
    public let pageURL: URL
    /// The .dmg itself, when the release has one.
    public let downloadURL: URL?
}

public enum UpdateCheck {
    struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }

        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    /// Reads GitHub's "latest release" answer. Returns the update if it's newer than `current`.
    public static func update(fromLatestReleaseJSON data: Data, current: AppVersion) throws -> AvailableUpdate? {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tag_name), version > current else { return nil }
        let dmg = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return AvailableUpdate(version: version, pageURL: release.html_url, downloadURL: dmg?.browser_download_url)
    }
}

/// Checks the GitHub repository named in Info.plist (`SpiderUpdateRepo`, "owner/name")
/// for a newer release: on demand, and once a day when automatic checks are on.
@MainActor
@Observable
public final class UpdateChecker {
    public enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case failed(String)
    }

    public private(set) var status: Status = .idle
    public private(set) var lastChecked: Date?
    public let currentVersion: AppVersion

    public var checksAutomatically: Bool {
        didSet { defaults.set(checksAutomatically, forKey: Keys.automatic) }
    }

    public var availableUpdate: AvailableUpdate? {
        if case .available(let update) = status { update } else { nil }
    }

    @ObservationIgnored private let latestReleaseURL: URL
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let onNewUpdate: @MainActor (AvailableUpdate) -> Void
    @ObservationIgnored private var dailyTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "SpiderPomodoro", category: "updates")

    private enum Keys {
        static let automatic = "updates.automatic"
        static let announced = "updates.announcedVersion"
    }

    /// Reads the repository and version from the app's Info.plist.
    /// Nil when the app doesn't say which repository to check.
    /// - Parameter onNewUpdate: called once per new version found (for a notification).
    public convenience init?(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        onNewUpdate: @escaping @MainActor (AvailableUpdate) -> Void = { _ in }
    ) {
        guard let repo = bundle.object(forInfoDictionaryKey: "SpiderUpdateRepo") as? String,
              let versionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let version = AppVersion(versionText) else { return nil }
        self.init(repo: repo, currentVersion: version, defaults: defaults, session: session, onNewUpdate: onNewUpdate)
    }

    /// - Parameter repo: "owner/name" on GitHub.
    public init?(
        repo: String,
        currentVersion: AppVersion,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        onNewUpdate: @escaping @MainActor (AvailableUpdate) -> Void = { _ in }
    ) {
        guard !repo.isEmpty, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }
        latestReleaseURL = url
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.session = session
        self.onNewUpdate = onNewUpdate
        checksAutomatically = defaults.object(forKey: Keys.automatic) as? Bool ?? true
    }

    /// Checks shortly after launch, then once a day, while automatic checks are on.
    public func startAutomaticChecks() {
        guard dailyTask == nil else { return }
        dailyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            while !Task.isCancelled {
                guard let self else { return }
                if self.checksAutomatically { await self.check() }
                try? await Task.sleep(for: .seconds(24 * 3600))
            }
        }
    }

    public func check() async {
        guard status != .checking else { return }
        status = .checking
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SpiderPomodoro/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastChecked = Date()
            switch code {
            case 200:
                if let update = try UpdateCheck.update(fromLatestReleaseJSON: data, current: currentVersion) {
                    status = .available(update)
                    log.notice("Update available: \(update.version.description, privacy: .public)")
                    announceOnce(update)
                } else {
                    status = .upToDate
                }
            case 404:
                // No releases yet.
                status = .upToDate
            default:
                status = .failed("GitHub answered \(code)")
            }
        } catch {
            lastChecked = Date()
            status = .failed(error.localizedDescription)
            log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func announceOnce(_ update: AvailableUpdate) {
        guard defaults.string(forKey: Keys.announced) != update.version.description else { return }
        defaults.set(update.version.description, forKey: Keys.announced)
        onNewUpdate(update)
    }
}
