//
//  InternalSwitcher.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 24/12/2021.
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Foundation

class InternalSwitcher {

    // MARK: - Container

    var container: Container

    init(_ container: Container) {
        self.container = container
    }

    // MARK: - Switcher

    /**
     Switching to a new PHP version involves:
     - unlinking the current version
     - stopping the active services
     - linking the new desired version

     Please note that depending on which version is installed,
     the version that is switched to may or may not be identical to `php`
     (without @version).
     */
    func performSwitch(to version: String) async {
        Log.info("Switching to \(version), unlinking all versions...")
        let versions = getVersionsToBeHandled(version)

        await withTaskGroup(of: String.self, body: { group in
            for available in container.phpEnvs.availablePhpVersions {
                group.addTask {
                    await self.unlinkAndStopPhpVersion(available)
                    return available
                }
            }

            var unlinked: [String] = []
            for await version in group {
                unlinked.append(version)
            }

            Log.info("These versions have been unlinked: \(unlinked)")
            Log.info("Linking the new version \(version)!")

            for formula in versions {
                if container.valet.installed {
                    Log.info("Ensuring that the Valet configuration is valid...")
                    await self.ensureValetConfigurationIsValidForPhpVersion(formula)
                }

                Log.info("Will start PHP \(version)... (primary: \(version == formula))")
                await self.linkAndStartPhpVersion(formula, primary: (version == formula))
            }

            if container.valet.installed {
                Log.info("Restarting nginx, just to be sure!")
                await brew(container, "services restart nginx", sudo: true)
            }

            Log.info("The new version(s) have been linked!")
        })
    }

    /// Starts the active PHP version and those of isolated sites again, after an operation stopped them.
    func startPhpInUse(activeVersion: String?) async {
        await container.phpEnvs.detectPhpVersions()
        guard let activeVersion, container.phpEnvs.availablePhpVersions.contains(activeVersion) else {
            Log.warn("Could not start PHP again: PHP \(activeVersion ?? "none") is not available.")
            return
        }
        await performSwitch(to: activeVersion)
    }

    func getVersionsToBeHandled(_ primary: String) -> Set<String> {
        let isolated = container.valet.sites.filter { site in
            site.isolatedPhpVersion != nil
        }.map { site in
            return site.isolatedPhpVersion!.versionNumber.short
        }

        var versions: Set<String> = [primary]

        if container.valet.features.contains(.isolatedSites) {
            versions = versions.union(isolated)
        }

        return versions
    }

    func unlinkAndStopPhpVersion(_ version: String) async {
        let formula = (version == container.phpEnvs.brewPhpAlias) ? "php" : "php@\(version)"
        await brew(container, "unlink \(formula)")

        if container.valet.installed {
            await brew(container, "services stop \(formula)", sudo: true)
            Log.info("Unlinked and stopped services for \(formula)")
        } else {
            Log.info("Unlinked \(formula)")
        }
    }

    func linkAndStartPhpVersion(_ version: String, primary: Bool) async {
        let formula = (version == container.phpEnvs.brewPhpAlias) ? "php" : "php@\(version)"

        if primary {
            Log.info("\(formula) is the primary formula, linking...")
            await brew(container, "link \(formula) --overwrite --force")
        } else {
            Log.info("\(formula) is an isolated PHP version, not linking!")
        }

        if container.valet.installed {
            await brew(container, "services start \(formula)", sudo: true)

            if container.valet.features.contains(.isolatedSites) && primary {
                let socketVersion = version.replacing(".", with: "")
                await container.shell.pipe("ln -sF ~/.config/valet/valet\(socketVersion).sock ~/.config/valet/valet.sock")
                Log.info("Symlinked new socket version (valet\(socketVersion).sock → valet.sock).")
            }
        }
    }
}
