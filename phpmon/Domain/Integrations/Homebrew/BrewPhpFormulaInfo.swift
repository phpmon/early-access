//
//  BrewPhpFormulaInfo.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Foundation

/// Metadata from `brew info --json=v2 --installed`. The package version includes
/// the formula revision; PHP's own version output does not.
nonisolated struct BrewPhpFormulaInfo: Decodable, Sendable {
    let name: String
    let full_name: String
    let pinned: Bool
    let outdated: Bool
    let revision: Int
    let versions: Versions
    let urls: Urls

    struct Versions: Decodable, Sendable {
        let stable: String?
    }

    struct Urls: Decodable, Sendable {
        let stable: Source?
    }

    struct Source: Decodable, Sendable {
        let url: String
    }

    struct Response: Decodable {
        let formulae: [BrewPhpFormulaInfo]
    }

    var source: BrewPhpFormulaSource {
        guard let url = urls.stable?.url else {
            return .unknown
        }
        return BrewPhpFormulaSource.from(url: url, version: versions.stable)
    }

    var packageVersion: String? {
        guard let version = versions.stable else {
            return nil
        }
        return revision == 0 ? version : "\(version)_\(revision)"
    }
}

nonisolated struct BrewPhpInstallationReceipt: Decodable {
    let source: Source

    struct Source: Decodable {
        let tap: String?
    }
}
