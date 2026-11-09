//
//  BrewFormulaeHandler.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 21/03/2023.
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Foundation

protocol HandlesBrewPhpFormulae {
    var container: Container { get }
    var formulae: BrewFormulaeObservable { get }
    func loadPhpVersions(loadOutdated: Bool) async -> [BrewPhpFormula]
    func refreshPhpVersions(loadOutdated: Bool) async
}

extension HandlesBrewPhpFormulae {
    public func refreshPhpVersions(loadOutdated: Bool) async {
        let items = await loadPhpVersions(loadOutdated: loadOutdated)
        await container.phpEnvs.determinePhpAlias()
        formulae.phpVersions = items
    }
}

class BrewPhpFormulaeHandler: HandlesBrewPhpFormulae {
    // MARK: - Container

    let container: Container
    let formulae: BrewFormulaeObservable

    init(_ container: Container, formulae: BrewFormulaeObservable = BrewFormulaeObservable()) {
        self.container = container
        self.formulae = formulae
    }

    // MARK: - Methods

    public func loadPhpVersions(loadOutdated: Bool) async -> [BrewPhpFormula] {
        var installedFormulae: [BrewPhpFormulaInfo]?
        formulae.updateCheckFailed = false

        let infoCommand = "\(container.paths.brew) info --json=v2 --installed"
        let command = loadOutdated
            ? "\(container.paths.brew) update >/dev/null && \(infoCommand)"
            : infoCommand

        do {
            let (process, output) = try await container.shell.attach(
                command, didReceiveOutput: { _, _ in }, withTimeout: .minutes(2)
            )
            guard process.terminationStatus == 0 else {
                throw BrewCommandError(error: "Could not check PHP updates.", log: [output.err])
            }
            installedFormulae = try JSONDecoder().decode(
                BrewPhpFormulaInfo.Response.self, from: Data(output.out.utf8)
            ).formulae
        } catch {
            formulae.updateCheckFailed = true
            Log.err("Could not check PHP updates: \(error)")
        }

        let mainPhpUpgradeVersion = installedFormulae?
            .first { $0.name == "php" && $0.outdated && !$0.pinned }?
            .versions.stable.flatMap { try? VersionNumber.parse($0).short }
        var items: [BrewPhpFormula] = []
        for (version, formula) in Brew.phpVersionFormulae {
            let installation = container.phpEnvs.cachedPhpInstallations[version]
            let installedName = installation?.formulaName
            let container = self.container
            let tapName = version == container.phpEnvs.brewPhpAlias ? "php" : "php@\(version)"
            let sources = await runBlocking {
                let tapPath = "\(container.paths.tapPath)/shivammathur/homebrew-php/Formula/\(tapName).rb"
                let available = (try? container.filesystem.getStringFromFile(tapPath))
                    .map { BrewPhpFormulaSource.from($0) } ?? .unknown
                guard let installedName else {
                    return (available: available, installed: BrewPhpFormulaSource.unknown, tap: Optional<String>.none)
                }
                let root = "\(container.paths.optPath)/\(installedName)"
                let installed = (try? container.filesystem.getStringFromFile("\(root)/.brew/\(installedName).rb"))
                    .map { BrewPhpFormulaSource.from($0) } ?? .unknown
                let receipt = (try? container.filesystem.getStringFromFile("\(root)/INSTALL_RECEIPT.json"))
                    .flatMap { try? JSONDecoder().decode(BrewPhpInstallationReceipt.self, from: Data($0.utf8)) }
                return (available: available, installed: installed, tap: receipt?.source.tap)
            }

            // Receipts identify the installed tap. Do not compare it with a different tap's formula.
            let info = installedFormulae?.first { info in
                guard info.name == installedName else { return false }
                if let tap = sources.tap {
                    let fullName = tap == "homebrew/core" ? info.name : "\(tap)/\(info.name)"
                    return info.full_name == fullName || info.full_name == "\(tap)/\(info.name)"
                }
                return info.full_name == formula || info.full_name == installedName
            }

            // Normal releases do not need a saved source commit for Homebrew's version check.
            // Development builds still need their saved formula to compare nightly commits.
            var installedSource = sources.installed
            if installedSource == .unknown, let version = installation?.installedVersion,
               !version.lowercased().contains("dev") {
                installedSource = .release(version: version)
            }
            let source = installation == nil ? sources.available : installedSource
            let prerelease = source.isPrerelease ?? installation?.installedVersion.map {
                PhpInstallation.isPrereleaseVersion($0)
            }
            let updateCheck: BrewPhpUpdateCheck
            if let info, installation != nil {
                updateCheck = BrewPhpUpdateCheck.compare(
                    installed: installedSource, available: info.source,
                    homebrewUpgrade: info.outdated ? info.packageVersion : nil
                )
            } else {
                updateCheck = .unknown
            }

            items.append(BrewPhpFormula(
                container,
                name: info?.full_name ?? installedName.map { name in
                    guard let tap = sources.tap, tap != "homebrew/core" else { return name }
                    return "\(tap)/\(name)"
                } ?? formula,
                displayName: "PHP \(version)",
                installedVersion: installation.map { $0.installedVersion ?? $0.versionNumber.text },
                updateCheck: updateCheck,
                prerelease: prerelease,
                isPinned: info?.pinned ?? false,
                mainPhpUpgradeVersion: mainPhpUpgradeVersion
            ))
        }
        return items.sorted { $0.displayName > $1.displayName }
    }
}
