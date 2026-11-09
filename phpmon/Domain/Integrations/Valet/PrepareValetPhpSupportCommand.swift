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
        } catch {
            throw BrewCommandError(error: error.localizedDescription, log: [error.localizedDescription])
        }
    }

    private func prepare(shell: ShellProtocol, _ onProgress: @escaping @Sendable (BrewCommandProgress) -> Void) async throws {
        guard !versions.isEmpty, container.valet.installed else { return }
        onProgress(.create(value: 0.05, title: getCommandTitle(), description: "phpman.valet.checking".localized))

        let container = self.container
        await runBlocking { container.paths.detectBinaryPaths() }
        guard let composer = container.paths.composer else {
            throw ValetPhpSupportError.unrecognizedInstallation
        }

        var source = try await readSource(composer: composer, shell: shell)
        var list = try ValetPhpVersionList(source.content)
        var current = try await readVersion(shell: shell)
        var owned = try await ownedVersions(in: source, valetVersion: current.text)
        _ = try list.missingVersions(from: versions, temporaryVersions: owned)
        let installedVersions = Set(container.phpEnvs.cachedPhpInstallations.keys)
        let sourcePath = source.path
        let candidates = try await runBlocking {
            try ValetPhpSupportEdits(container: container).restorationCandidates(at: sourcePath)
        }
        // A cancelled edit after Composer updates Valet must not forget installed temporary support.
        // Ignore historical series that this Valet release no longer permits us to add.
        let temporaryVersions = candidates.filter {
            (try? list.missingVersions(from: [$0], temporaryVersions: owned)) != nil
        }
        let installedTemporaryVersions = await runBlocking {
            temporaryVersions.filter {
                installedVersions.contains($0)
                    || container.filesystem.fileExists("\(container.paths.optPath)/php@\($0)/bin/php")
            }
        }
        let requiredVersions = versions.union(installedTemporaryVersions)
        guard !requiredVersions.isSubset(of: list.versions) else { return }

        if let installed = try await updateIfNeeded(current: current, composer: composer, shell: shell, onProgress) {
            // Composer may have replaced the package, moved it, or added support itself.
            source = try await readSource(composer: composer, shell: shell)
            list = try ValetPhpVersionList(source.content)
            current = installed
            owned = try await ownedVersions(in: source, valetVersion: current.text)
        }

        let (updated, missing) = try list.adding(requiredVersions, temporaryVersions: owned)
        guard !missing.isEmpty else { return }
        let valetVersion = current.text
        guard await approval(.addVersions(missing.sorted(), valetVersion: valetVersion, file: source.path)) else {
            throw ValetPhpSupportError.cancelled
        }
        let file = source.path
        let original = source.content
        onProgress(.create(value: 0.05, title: getCommandTitle(), description: "phpman.valet.patching".localized))
        try await replaceSupportList(
            path: file, shell: shell, valetVersion: valetVersion,
            before: (original, owned), after: (updated, owned.union(missing))
        )
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
                    error: "Could not restore Valet after its syntax check failed.",
                    log: [validationError.localizedDescription, error.localizedDescription]
                )
            }
            throw validationError
        }
        let confirmed = try await runBlocking { try container.filesystem.getStringFromFile(path) }
        guard confirmed == updated else { throw ValetPhpSupportError.sourceChanged }
    }

    private func updateIfNeeded(
        current: VersionNumber,
        composer: String,
        shell: ShellProtocol,
        _ onProgress: @escaping @Sendable (BrewCommandProgress) -> Void
    ) async throws -> VersionNumber? {
        let latest = try await Packagist.getLatestStableVersion(packageName: "laravel/valet", container: container)
        guard latest.major == current.major,
              Constants.ValetSupportedPhpVersionMatrix[latest.major] != nil else {
            throw ValetPhpSupportError.manualMajorUpgradeRequired
        }
        container.valet.latestVersion = latest
        guard current.isOlderThan(latest) else { return nil }
        guard await approval(.update(current: current.text, latest: latest.text)) else {
            throw ValetPhpSupportError.cancelled
        }
        onProgress(.create(value: 0.05, title: getCommandTitle(), description: "phpman.valet.updating".localized))
        try await run(shell: shell, CommandCatalog.ValetSupport.update(composer: composer), onProgress)
        let installed = try await readVersion(shell: shell)
        guard !installed.isOlderThan(latest), installed.major == latest.major else {
            throw ValetPhpSupportError.updateIncomplete
        }
        return installed
    }

    /// Undo only recorded additions after the corresponding PHP installations are gone.
    func removeOwnedSupport(shell: ShellProtocol) async throws {
        let absent = versions.subtracting(container.phpEnvs.cachedPhpInstallations.keys)
        let edits = ValetPhpSupportEdits(container: container)
        let tracked = try await runBlocking { try edits.hasEdits(for: absent) }
        guard !absent.isEmpty, tracked, container.valet.installed else { return }
        let container = self.container
        let stillInstalled = await runBlocking {
            absent.contains { container.filesystem.fileExists("\(container.paths.optPath)/php@\($0)/bin/php") }
        }
        guard !stillInstalled else { return }
        await runBlocking { container.paths.detectBinaryPaths() }
        guard let composer = container.paths.composer else {
            throw ValetPhpSupportError.unrecognizedInstallation
        }
        let source = try await readSource(composer: composer, shell: shell)
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

    private func readSource(composer: String, shell: ShellProtocol) async throws -> (path: String, content: String) {
        let directory = try await checkedOutput(CommandCatalog.ValetSupport.vendorDirectory(composer: composer), shell: shell)
        guard directory.hasPrefix("/"), !directory.contains("\n") else {
            throw ValetPhpSupportError.unrecognizedInstallation
        }
        let root = URL(fileURLWithPath: directory).appendingPathComponent("laravel/valet").standardizedFileURL.path
        let container = self.container
        return try await runBlocking {
            let filesystem = container.filesystem!
            var executable = container.paths.valet
            var visited: Set<String> = []
            while filesystem.isSymlink(executable) {
                guard visited.count < 32, visited.insert(executable).inserted else {
                    throw ValetPhpSupportError.unrecognizedInstallation
                }
                let target = try filesystem.getDestinationOfSymlink(executable)
                executable = target.hasPrefix("/") ? target
                    : URL(fileURLWithPath: executable).deletingLastPathComponent().appendingPathComponent(target).standardizedFileURL.path
            }
            guard executable == "\(root)/valet" else {
                throw ValetPhpSupportError.unrecognizedInstallation
            }
            let path = "\(root)/cli/Valet/Brew.php"
            return (path, try filesystem.getStringFromFile(path))
        }
    }

    private func checkedOutput(_ command: String, shell: ShellProtocol) async throws -> String {
        let (process, output) = try await shell.attach(command, didReceiveOutput: { _, _ in }, withTimeout: .minutes(2))
        guard process.terminationStatus == 0 else {
            throw BrewCommandError(error: "Could not prepare Valet PHP support.", log: [output.err, output.out])
        }
        return output.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
