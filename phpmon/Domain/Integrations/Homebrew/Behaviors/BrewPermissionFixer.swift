//
//  BrewPermissionFixer.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 23/04/2023.
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Foundation

class BrewPermissionFixer {

    // MARK: - Container

    var container: Container

    init(_ container: Container) {
        self.container = container
    }

    // MARK: - Variables

    var broken: [DueOwnershipFormula] = []

    /**
     Gives the folders of the given PHP versions back to the user before Homebrew changes them.

     Valet runs PHP as root, and `sudo brew services start` then makes the formula's `bin` and
     `sbin` folders root-owned. Homebrew cannot remove or replace a keg with root-owned folders,
     so upgrades, reinstalls and removals fail.

     Valet 3 and newer restore ownership whenever they stop PHP, and PHP Monitor may run Valet
     without a password. So this stops PHP through Valet first, and only asks for administrator
     access for folders that remain root-owned: with Valet 2, or for versions that are not running.

     - Parameter versions: The PHP versions that Homebrew is about to change.
     - Returns: Whether PHP services were stopped, so the caller can start the ones in use again.
     */
    @discardableResult
    public func restoreOwnership(of versions: Set<String>) async throws -> Bool {
        await determineBrokenFormulae(limitedTo: versions)
        if broken.isEmpty {
            return false
        }

        if container.valet.installed, (container.valet.version?.major ?? 0) >= 3 {
            Log.info("Stopping PHP through Valet to restore ownership of: \(broken.map { $0.path })")
            await container.shell.pipe("sudo \(container.paths.valet) stop php")
            await determineBrokenFormulae(limitedTo: versions)
            if broken.isEmpty {
                return true
            }
        }

        // The admin prompt plus `brew services stop` and the recursive `chown`
        // block until they complete, so the runner keeps them off the main actor.
        _ = try await container.privilegedCommandRunner.runSimpleShellAsAdmin(
            buildBrokenFormulaeScript(), reason: .restoreHomebrewOwnership
        )

        Log.info("Ownership was taken of the folder(s) at: " + broken
            .map({ $0.path })
            .joined(separator: ", "))
        return true
    }

    /**
     Determines which of the given PHP versions have a root-owned `bin` or `sbin` folder.
     */
    private func determineBrokenFormulae(limitedTo versions: Set<String>) async {
        broken = []
        let container = self.container
        let alias = container.phpEnvs.brewPhpAlias

        for version in versions.sorted() {
            let formula = version == alias ? "php" : "php@\(version)"
            let path = "\(container.paths.optPath)/\(formula)"
            let owned = await runBlocking {
                ["bin", "sbin"].filter { container.filesystem.isOwnedByRoot("\(path)/\($0)") }
            }

            if !owned.isEmpty {
                Log.warn("\(formula) has folders owned by root: \(owned)")
            }
            broken += owned.map { DueOwnershipFormula(formula: formula, path: "\(path)/\($0)") }
        }
    }

    /**
     Generates the appropriate AppleScript script required to restore permissions.
     This script also stops the services prior to taking ownership, which is requirement.
     */
    private func buildBrokenFormulaeScript() -> String {
        return broken
            .map { b in
                return """
                    \(container.paths.brew) services stop \(b.formula) \
                    && chown -R \(container.paths.whoami):admin \(b.path)
                    """
            }
            .joined(
                separator: " && "
            )
    }

    struct DueOwnershipFormula {
        let formula: String
        let path: String
    }
}
