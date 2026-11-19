//
//  ValetPhpSupportEdits.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Cocoa
import CryptoKit

/// A write-ahead record: either hash identifies the edit's ownership after an interrupted write or rollback.
/// Unknown files and entries that were already present are never adopted as PHP Monitor edits.
nonisolated struct ValetPhpSupportEdits {
    let container: Container

    var path: String {
        "\(container.paths.homePath)/.config/phpmon/valet-php-support.json"
    }

    struct Snapshot: Codable {
        let hash: String
        let versions: Set<String>
    }

    struct Record: Codable {
        let valetVersion: String
        let before: Snapshot
        let after: Snapshot
    }

    func hasEdits(for versions: Set<String>) throws -> Bool {
        return try read().values.contains { record in
            !record.before.versions.union(record.after.versions).isDisjoint(with: versions)
        }
    }

    func ownedVersions(at file: String, valetVersion: String, content: String) throws -> Set<String> {
        guard let record = try read()[file], record.valetVersion == valetVersion else {
            return []
        }
        let hash = Self.hash(content)
        if hash == record.after.hash {
            return record.after.versions
        }
        if hash == record.before.hash {
            return record.before.versions
        }
        throw ValetPhpSupportError.ownershipChanged
    }

    /// Historical entries are only candidates for a new consent prompt, never proof of current ownership.
    func restorationCandidates(at file: String) throws -> Set<String> {
        guard let record = try read()[file] else {
            return []
        }
        return record.before.versions.union(record.after.versions)
    }

    func record(
        file: String, valetVersion: String,
        before: (content: String, versions: Set<String>), after: (content: String, versions: Set<String>)
    ) throws {
        var records = try read()
        records[file] = Record(
            valetVersion: valetVersion,
            before: Snapshot(hash: Self.hash(before.content), versions: before.versions),
            after: Snapshot(hash: Self.hash(after.content), versions: after.versions)
        )
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
        if !container.filesystem.directoryExists(directory) {
            try container.filesystem.createDirectory(directory, withIntermediateDirectories: true)
        }
        let data = try JSONEncoder().encode(records)
        try container.filesystem.writeAtomicallyToFile(path, content: String(data: data, encoding: .utf8)!)
    }

    private func read() throws -> [String: Record] {
        guard container.filesystem.fileExists(path) else {
            return [:]
        }
        let contents = try container.filesystem.getStringFromFile(path)
        return try JSONDecoder().decode([String: Record].self, from: Data(contents.utf8))
    }

    private static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// A request to add PHP versions to Valet's support list, shown to the user for consent.
nonisolated struct ValetPhpSupportChange: Sendable {
    let versions: [String]
    let valetVersion: String
    let file: String
    /// A newer Valet release that the launch-time update check found, if any.
    let newerValetVersion: String?

    var title: String {
        return "phpman.valet.add.title".localized(names)
    }

    var message: String {
        var paragraphs = ["phpman.valet.add.description".localized(valetVersion, names, file)]
        if let newerValetVersion {
            paragraphs.append("phpman.valet.add.newer_valet".localized(newerValetVersion, names))
        }
        paragraphs.append("phpman.valet.add.disclaimer".localized(names))
        return paragraphs.joined(separator: "\n\n")
    }

    private var names: String {
        return versions.joined(separator: ", ")
    }
}

typealias ValetPhpSupportApproval = @MainActor @Sendable (ValetPhpSupportChange) async -> Bool

extension ValetPhpSupportChange {
    /// Ask for consent as a sheet on the window that started the operation.
    @MainActor func confirm(onWindow window: NSWindow?) async -> Bool {
        guard let window else { return false }
        return await Alert.confirm(
            onWindow: window,
            messageText: title,
            informativeText: message,
            buttonTitle: "phpman.valet.confirm_patch.button".localized,
            secondButtonTitle: "generic.cancel".localized,
            style: .warning
        )
    }
}
