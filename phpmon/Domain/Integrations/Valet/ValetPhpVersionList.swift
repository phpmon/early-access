//
//  ValetPhpVersionList.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Foundation

/// A deliberately narrow parser for Valet's literal PHP support array.
/// Refuse expressions and unfamiliar layouts instead of rewriting PHP code we do not understand.
nonisolated struct ValetPhpVersionList {
    let content: String
    let versions: Set<String>
    private let insertionIndex: String.Index
    private let bodyRange: Range<String.Index>

    init(_ content: String) throws {
        guard content.contains("namespace Valet;"), content.contains("class Brew") else {
            throw ValetPhpSupportError.unrecognizedSource
        }
        let declaration = try NSRegularExpression(pattern:
            #"(?m)^    (?:public )?const SUPPORTED_PHP_VERSIONS = \[\n([\s\S]*?)^    \];"#)
        let matches = declaration.matches(in: content, range: NSRange(content.startIndex..., in: content))
        guard matches.count == 1, let match = matches.first,
              let bodyRange = Range(match.range(at: 1), in: content) else {
            throw ValetPhpSupportError.unrecognizedSource
        }
        let body = String(content[bodyRange])
        let entries = body.split(separator: "\n", omittingEmptySubsequences: false)
        let entry = try NSRegularExpression(pattern: #"^        '(php(?:@\d+\.\d+)?)',$"#)
        var versions: Set<String> = []
        for line in entries where !line.isEmpty {
            let text = String(line)
            guard let match = entry.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else {
                throw ValetPhpSupportError.unrecognizedSource
            }
            guard versions.insert(String(text[range])).inserted else {
                throw ValetPhpSupportError.unrecognizedSource
            }
        }
        guard versions.contains("php"), versions.count > 1,
              let alias = content.range(of: "        'php',\n", range: bodyRange) else {
            throw ValetPhpSupportError.unrecognizedSource
        }
        self.content = content
        self.versions = Set(versions.filter { $0 != "php" }.map { $0.replacing("php@", with: "") })
        self.insertionIndex = alias.upperBound
        self.bodyRange = bodyRange
    }

    func missingVersions(from requested: Set<String>, temporaryVersions: Set<String> = []) throws -> Set<String> {
        let missing = requested.subtracting(versions)
        // Our temporary entries do not raise Valet's official PHP support boundary.
        guard let newest = versions.subtracting(temporaryVersions).compactMap({ VersionNumber.make(from: $0) })
            .max(by: { $0.isOlderThan($1) }) else {
            throw ValetPhpSupportError.unrecognizedSource
        }
        for version in missing {
            guard let parsed = VersionNumber.make(from: version), parsed.patch == nil,
                  parsed.isNewerThan(newest) else {
                throw ValetPhpSupportError.unsupportedVersion
            }
        }
        return missing
    }

    func adding(_ requested: Set<String>, temporaryVersions: Set<String> = []) throws -> (content: String, addedVersions: Set<String>) {
        let missing = try missingVersions(from: requested, temporaryVersions: temporaryVersions)
        let entries = missing.sorted { $0.versionCompare($1) == .orderedDescending }
            .map { "        'php@\($0)',\n" }.joined()
        var updated = content
        updated.insert(contentsOf: entries, at: insertionIndex)
        return (updated, missing)
    }

    func removing(_ requested: Set<String>) -> String {
        var body = String(content[bodyRange])
        for version in requested.intersection(versions) {
            body = body.replacing("        'php@\(version)',\n", with: "")
        }
        var updated = content
        updated.replaceSubrange(bodyRange, with: body)
        return updated
    }
}

nonisolated enum ValetPhpSupportError: Error, LocalizedError {
    case unrecognizedInstallation
    case unrecognizedSource
    case unsupportedVersion
    case manualMajorUpgradeRequired
    case updateIncomplete
    case sourceChanged
    case sourceNotWritable
    case cancelled
    case ownershipChanged

    var errorDescription: String? {
        switch self {
        case .unrecognizedInstallation:
            return "Could not verify that Composer and PHP Monitor use the same Valet installation."
        case .unrecognizedSource:
            return "Valet's PHP support list has an unfamiliar format. No changes were made to the list."
        case .unsupportedVersion:
            return "PHP Monitor can only extend Valet's support list with newer PHP series."
        case .manualMajorUpgradeRequired:
            return "Update Valet to the latest major version manually before using this PHP version."
        case .updateIncomplete:
            return "Valet did not reach the latest stable version. Check Composer's version constraints."
        case .sourceChanged:
            return "Valet changed during the operation. Stop other Composer operations and try again."
        case .sourceNotWritable:
            return "Valet's PHP support list is not writable. No changes were made to the list."
        case .cancelled:
            return "The Valet change was cancelled."
        case .ownershipChanged:
            return "Valet's file changed since PHP Monitor edited it. Its support entries were left untouched."
        }
    }
}
