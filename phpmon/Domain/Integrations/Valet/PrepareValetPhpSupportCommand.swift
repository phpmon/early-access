//
//  PrepareValetPhpSupportCommand.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Foundation

class PrepareValetPhpSupportCommand: BrewCommand {
    let container: Container
    let versions: Set<String>
    private(set) var addedVersions: Set<String> = []
    /// The requested versions that Valet does not list, for error messages.
    private(set) var unlistedVersions: Set<String> = []
    let approval: ValetPhpSupportApproval

    init(_ container: Container, versions: Set<String>, approval: @escaping ValetPhpSupportApproval = { _ in false }) {
        self.container = container
        self.versions = versions
        self.approval = approval
    }

    nonisolated func getCommandTitle() -> String {
        return "phpman.busy.title".localized
    }

    nonisolated func execute(shell: ShellProtocol, onProgress: @escaping @Sendable (BrewCommandProgress) -> Void) async throws {
        do {
            try await prepare(shell: shell, onProgress)
        } catch ValetPhpSupportError.cancelled {
            throw ValetPhpSupportError.cancelled
        } catch let error as BrewCommandError {
            throw error
        } catch ValetPhpSupportError.unrecognizedSource {
            // The parser knows neither the file nor the versions, so name them here.
            let container = self.container
            let file = await runBlocking { try? container.paths.valetPackageDirectory() + "/cli/Valet/Brew.php" }
            let unlisted = await unlistedVersions
            let message = ValetPhpSupportError.unrecognizedSourceMessage(
                versions: (unlisted.isEmpty ? versions : unlisted).sorted { $0.versionCompare($1) == .orderedDescending },
                file: file
            )
            throw BrewCommandError(error: message, log: [message])
        } catch {
            throw BrewCommandError(error: error.localizedDescription, log: [error.localizedDescription])
        }
    }

    private func prepare(shell: ShellProtocol, _ onProgress: @escaping @Sendable (BrewCommandProgress) -> Void) async throws {
        addedVersions = []
        unlistedVersions = []
        guard !versions.isEmpty, container.valet.installed else { return }
        onProgress(.create(value: 0.05, title: getCommandTitle(), description: "phpman.valet.checking".localized))

        guard let installedCandidates = try await candidatesRequiringPreparation(shell: shell) else {
            Log.info("Continuing without editing Valet's PHP support list.")
            return
        }
        let source = try await readSource()
        let list = try ValetPhpVersionList(source.content)
        let current = try await readVersion(shell: shell)
        let owned = try await ownedVersions(in: source, valetVersion: current.text)
        unlistedVersions = versions.subtracting(list.versions)
        _ = try list.missingVersions(from: versions, temporaryVersions: owned)
        // Updating Valet replaces the file, including temporary entries for PHP versions that are still
        // installed. Offer those again, but skip series that this Valet release no longer permits us to add.
        let installedTemporaryVersions = installedCandidates.filter { version in
            list.canSupport(version, temporaryVersions: owned)
        }
        let requiredVersions = versions.union(installedTemporaryVersions)
        guard !requiredVersions.isSubset(of: list.versions) else { return }

        let (updated, missing) = try list.adding(requiredVersions, temporaryVersions: owned)
        guard !missing.isEmpty else { return }
        // Only mention a newer Valet that the launch-time update check already found.
        let newerValet = container.valet.latestVersion.flatMap { current.isOlderThan($0) ? $0.text : nil }
        let change = ValetPhpSupportChange(
            versions: missing.sorted { $0.versionCompare($1) == .orderedDescending },
            valetVersion: current.text, file: source.path, newerValetVersion: newerValet
        )
        guard await approval(change) else {
            throw ValetPhpSupportError.cancelled
        }
        onProgress(.create(value: 0.05, title: getCommandTitle(), description: "phpman.valet.patching".localized))
        try await replaceSupportList(
            path: source.path, shell: shell, valetVersion: current.text,
            before: (source.content, owned), after: (updated, owned.union(missing))
        )
        addedVersions = missing
    }

    /// Return nil when Homebrew can proceed without preparing Valet.
    /// Otherwise, return the installed versions that have recorded temporary support.
    private func candidatesRequiringPreparation(shell: ShellProtocol) async throws -> Set<String>? {
        let container = self.container
        let source: (path: String, content: String)
        let list: ValetPhpVersionList
        do {
            source = try await readSource()
            list = try ValetPhpVersionList(source.content)
        } catch {
            var major = container.valet.version?.major
            if major == nil {
                major = try? await readVersion(shell: shell).major
            }
            let supported = major.flatMap { Constants.ValetPhpVersionsWithoutEdits[$0] }
            unlistedVersions = versions.subtracting(supported ?? [])
            guard let major, let supported, versions.isSubset(of: supported) else { throw error }
            Log.warn("Could not read Valet's PHP list. Continuing with known support for Valet \(major).")
            return nil
        }

        let alreadySupported = versions.isSubset(of: list.versions)
        if alreadySupported, let major = container.valet.version?.major,
           let supported = Constants.ValetPhpVersionsWithoutEdits[major], versions.isSubset(of: supported) {
            return nil
        }
        let installedVersions = Set(container.phpEnvs.cachedPhpInstallations.keys)
        let sourcePath = source.path
        let edits = ValetPhpSupportEdits(container: container)
        let candidates: Set<String>
        do {
            candidates = try await runBlocking { try edits.restorationCandidates(at: sourcePath) }
        } catch {
            guard alreadySupported else { throw error }
            Log.warn("Valet already supports the requested PHP versions. Skipping unreadable temporary support records.")
            return nil
        }
        let installedCandidates = await runBlocking {
            candidates.filter {
                installedVersions.contains($0) || container.filesystem.fileExists("\(container.paths.optPath)/php@\($0)/bin/php")
            }
        }
        guard !alreadySupported || !installedCandidates.isSubset(of: list.versions) else { return nil }
        return installedCandidates
    }

    private func ownedVersions(in source: (path: String, content: String), valetVersion: String) async throws -> Set<String> {
        let edits = ValetPhpSupportEdits(container: container)
        return try await runBlocking {
            try edits.ownedVersions(at: source.path, valetVersion: valetVersion, content: source.content)
        }
    }

    private func replaceSupportList(
        path: String, shell: ShellProtocol, valetVersion: String,
        before: (content: String, versions: Set<String>), after: (content: String, versions: Set<String>)
    ) async throws {
        let container = self.container
        let original = before.content
        let updated = after.content
        try await runBlocking {
            guard try container.filesystem.getStringFromFile(path) == original else {
                throw ValetPhpSupportError.sourceChanged
            }
            guard container.filesystem.isWriteableFile(path) else {
                throw ValetPhpSupportError.sourceNotWritable
            }
            // Persist ownership before the file changes, so an interrupted write remains recoverable.
            try ValetPhpSupportEdits(container: container).record(
                file: path, valetVersion: valetVersion, before: before, after: after
            )
            try container.filesystem.writeAtomicallyToFile(path, content: updated)
        }

        do {
            _ = try await checkedOutput(CommandCatalog.ValetSupport.lint(php: container.paths.php, path: path), shell: shell)
        } catch {
            let validationError = error
            do {
                try await runBlocking {
                    // Never overwrite a concurrent Composer update while rolling back.
                    guard try container.filesystem.getStringFromFile(path) == updated else {
                        throw ValetPhpSupportError.sourceChanged
                    }
                    try container.filesystem.writeAtomicallyToFile(path, content: original)
                }
            } catch {
                throw BrewCommandError(
                    error: "phpman.valet.errors.restore_failed".localized,
                    log: [validationError.localizedDescription, error.localizedDescription]
                )
            }
            throw validationError
        }
        let confirmed = try await runBlocking { try container.filesystem.getStringFromFile(path) }
        guard confirmed == updated else { throw ValetPhpSupportError.sourceChanged }
    }

    /// Undo only recorded additions after the corresponding PHP installations are gone.
    func removeOwnedSupport(shell: ShellProtocol, for candidates: Set<String>? = nil) async throws {
        let possiblyAbsent = (candidates ?? versions).subtracting(container.phpEnvs.cachedPhpInstallations.keys)
        guard !possiblyAbsent.isEmpty, container.valet.installed else { return }
        let edits = ValetPhpSupportEdits(container: container)
        let container = self.container
        let absent = await runBlocking {
            possiblyAbsent.filter { !container.filesystem.fileExists("\(container.paths.optPath)/php@\($0)/bin/php") }
        }
        guard !absent.isEmpty, try await runBlocking({ try edits.hasEdits(for: absent) }) else { return }
        let source = try await readSource()
        let version = try await readVersion(shell: shell).text
        let path = source.path
        let original = source.content
        let owned = try await runBlocking { try edits.ownedVersions(at: path, valetVersion: version, content: original) }
        let removing = owned.intersection(absent)
        guard !removing.isEmpty else { return }
        let updated = try ValetPhpVersionList(original).removing(removing)
        try await replaceSupportList(
            path: path, shell: shell, valetVersion: version,
            before: (original, owned), after: (updated, owned.subtracting(removing))
        )
    }

    private func readVersion(shell: ShellProtocol) async throws -> VersionNumber {
        let output = try await checkedOutput(CommandCatalog.ValetSupport.version(valet: container.paths.valet), shell: shell)
        guard output.range(of: #"^Laravel Valet \d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              let version = try? VersionNumber.parse(output) else {
            throw ValetPhpSupportError.unrecognizedInstallation
        }
        container.valet.version = version
        return version
    }

    /// Read `Brew.php` from the package that the `valet` command resolves to.
    private func readSource() async throws -> (path: String, content: String) {
        let container = self.container
        return try await runBlocking {
            let path = try container.paths.valetPackageDirectory() + "/cli/Valet/Brew.php"
            return (path, try container.filesystem.getStringFromFile(path))
        }
    }

    private func checkedOutput(_ command: String, shell: ShellProtocol) async throws -> String {
        let (process, output) = try await shell.attach(command, didReceiveOutput: { _, _ in }, withTimeout: .minutes(2))
        guard process.terminationStatus == 0 else {
            throw BrewCommandError(error: "phpman.valet.errors.prepare_failed".localized, log: [output.err, output.out])
        }
        return output.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
