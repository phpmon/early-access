//
//  BrewPhpFormula.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 17/03/2023.
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Foundation

struct BrewPhpFormula: Equatable, Sendable {

    /// The dependency container.
    let container: Container

    /// Name of the formula.
    let name: String

    /// The human readable name for this formula.
    let displayName: String

    /// The version of the formula that is currently installed.
    let installedVersion: String?

    /// The result of checking this installation for updates.
    let updateCheck: BrewPhpUpdateCheck

    let isPinned: Bool

    let releaseStatus: PhpReleaseStatus
    let buildDate: String?

    /// The series installed automatically by an available main-formula upgrade.
    let mainPhpUpgradeVersion: String?

    /// Whether this formula's associated Homebrew file exists.
    var hasFormulaFile: Bool = false

    /// Whether the formula is currently installed.
    var isInstalled: Bool {
        return installedVersion != nil
    }

    init(
        _ container: Container,
        name: String,
        displayName: String,
        installedVersion: String?,
        updateCheck: BrewPhpUpdateCheck = .unknown,
        releaseStatus: PhpReleaseStatus = .unknown,
        isPinned: Bool = false,
        mainPhpUpgradeVersion: String? = nil,
        buildDate: String? = nil
    ) {
        self.container = container
        self.name = name
        self.displayName = displayName
        self.installedVersion = installedVersion
        self.updateCheck = updateCheck
        self.isPinned = isPinned
        self.releaseStatus = releaseStatus
        self.buildDate = buildDate
        self.mainPhpUpgradeVersion = mainPhpUpgradeVersion
        self.hasFormulaFile = checkFormulaFile()
    }

    /// Whether the formula can be upgraded.
    var hasUpgrade: Bool {
        return update != nil && !isPinned
    }

    /// Whether this formula alias is different.
    var hasUpgradedFormulaAlias: Bool {
        return mainPhpUpgradeVersion != nil && self.shortVersion == mainPhpUpgradeVersion
            && mainPhpUpgradeVersion != container.phpEnvs.brewPhpAlias
    }

    // `nonisolated`: pure version comparison read by off-main brew command orchestration.
    nonisolated var seriesToRestoreAfterUpgrade: String? {
        guard name.split(separator: "/").last == "php",
              let installedVersion, case let .upgrade(version) = update,
              let installed = try? VersionNumber.parse(installedVersion),
              let upgrade = try? VersionNumber.parse(version),
              upgrade.short != installed.short else {
            return nil
        }
        return installed.short
    }

    nonisolated var update: BrewPhpUpdate? {
        if case let .available(update) = updateCheck {
            return update
        }
        return nil
    }

    /// The associated Homebrew folder with this PHP formula.
    var homebrewFolder: String {
        var resolved = name
            .replacing("shivammathur/php/", with: "")

        if let alias = container.phpEnvs.brewPhpAlias {
            resolved = resolved.replacing("php@" + alias, with: "php")
        }

        return "\(container.paths.optPath)/\(resolved)/bin"
    }

    /// The short version associated with this formula, if installed.
    var shortVersion: String? {
        guard let version = self.installedVersion else {
            return self.displayName.replacing("PHP ", with: "")
        }

        return (try? VersionNumber.parse(version))?.short
    }

    /// A quick variable that you can check to see if the install is unhealthy.
    /// Will report true if no health information is available.
    var healthy: Bool {
        return isHealthy() ?? true
    }

    /**
     Verify whether the formula file exists (sourced via `shivammathur/homebrew-php`).
     If it does not exist, the formula cannot be installed.
     */
    private func checkFormulaFile() -> Bool {
        guard let version = shortVersion else {
            return false
        }

        var path = "\(container.paths.tapPath)/shivammathur/homebrew-php/Formula/php@\(version).rb"

        if let alias = container.phpEnvs.brewPhpAlias {
            path = path.replacing("php@" + alias, with: "php")
        }

        return container.filesystem.fileExists(path)
    }

    /**
     * Determines if this PHP installation is healthy.
     * Uses the cached installation health check as basis.
     */
    public func isHealthy() -> Bool? {
        guard let shortVersion = self.shortVersion else {
            return nil
        }

        return container.phpEnvs.cachedPhpInstallations[shortVersion]?
            .isHealthy ?? nil
    }

    nonisolated static func == (lhs: BrewPhpFormula, rhs: BrewPhpFormula) -> Bool {
        return lhs.name == rhs.name
            && lhs.displayName == rhs.displayName
            && lhs.installedVersion == rhs.installedVersion
            && lhs.updateCheck == rhs.updateCheck
            && lhs.isPinned == rhs.isPinned
            && lhs.releaseStatus == rhs.releaseStatus
            && lhs.buildDate == rhs.buildDate
            && lhs.mainPhpUpgradeVersion == rhs.mainPhpUpgradeVersion
            && lhs.hasFormulaFile == rhs.hasFormulaFile
    }
}
