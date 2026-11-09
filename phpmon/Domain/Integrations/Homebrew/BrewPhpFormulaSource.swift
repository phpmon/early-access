//
//  BrewPhpFormulaSource.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Foundation

nonisolated enum BrewPhpFormulaSource: Equatable, Sendable {
    case release(version: String)
    case snapshot(commit: String)
    case unknown

    func releaseStatus(installedVersion: String? = nil) -> PhpReleaseStatus {
        let installedKind = installedVersion.flatMap(PhpPrerelease.from)
        switch self {
        case .snapshot:
            return .prerelease(installedKind ?? .nightly)
        case let .release(version):
            let status = PhpReleaseStatus(version: version)
            if case .prerelease = status, let installedKind {
                return .prerelease(installedKind)
            }
            return status
        case .unknown:
            return installedVersion.map { PhpReleaseStatus(version: $0) } ?? .unknown
        }
    }

    /// Reads the source declarations saved in a keg, without evaluating Ruby.
    /// Only direct class-level declarations are accepted; resource and HEAD URLs are ignored.
    static func from(_ content: String) -> Self {
        guard let url = capture(#"(?m)^  url ["']([^"']+)["']\s*$"#, in: content) else {
            return .unknown
        }
        return from(url: url, version: capture(#"(?m)^  version ["']([^"']+)["']\s*$"#, in: content))
    }

    static func from(url: String, version: String?) -> Self {
        guard let url = URL(string: url), url.scheme == "https" else {
            return .unknown
        }

        if url.host == "github.com", url.path.hasPrefix("/php/php-src/archive/") {
            guard let commit = capture(#"^/php/php-src/archive/([a-fA-F0-9]{40})\.tar\.gz$"#, in: url.path) else {
                return .unknown
            }
            return .snapshot(commit: commit.lowercased())
        }

        if let host = url.host, host == "php.net" || host.hasSuffix(".php.net"),
           let version = capture(#"/php-(\d+\.\d+\.\d+(?:(?:alpha|beta|RC)\d+)?)(?:\.tar\.(?:gz|bz2|xz)|\.tgz)$"#, in: url.path) {
            return .release(version: version)
        }

        // The tap also ships stable PHP releases built from its backports repository.
        if url.host == "github.com", url.path.hasPrefix("/shivammathur/php-src-backports/archive/"),
           let version, VersionNumber.make(from: version) != nil {
            return .release(version: version)
        }

        return .unknown
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}

nonisolated enum BrewPhpUpdate: Equatable, Sendable {
    case upgrade(version: String)
    case reinstallSnapshot(installedCommit: String, availableCommit: String)
    case reinstallRelease(version: String)

    var requiresReinstall: Bool {
        switch self {
        case .upgrade:
            return false
        case .reinstallSnapshot, .reinstallRelease:
            return true
        }
    }
}

nonisolated enum BrewPhpUpdateCheck: Equatable, Sendable {
    case unknown
    case current
    case available(BrewPhpUpdate)

    static func compare(
        installed: BrewPhpFormulaSource,
        available: BrewPhpFormulaSource,
        homebrewUpgrade: String?
    ) -> Self {
        if let version = homebrewUpgrade {
            return .available(.upgrade(version: version))
        }

        switch (installed, available) {
        case let (.snapshot(installedCommit), .snapshot(availableCommit)):
            return installedCommit == availableCommit
                ? .current
                : .available(.reinstallSnapshot(installedCommit: installedCommit, availableCommit: availableCommit))
        case let (.snapshot, .release(version)):
            return .available(.reinstallRelease(version: version))
        case let (.release(installedVersion), .release(availableVersion))
            where PhpInstallation.isPrereleaseVersion(installedVersion)
                && !PhpInstallation.isPrereleaseVersion(availableVersion):
            return .available(.reinstallRelease(version: availableVersion))
        case (.release, .release):
            return .current
        default:
            return .unknown
        }
    }
}
