//
//  BrewPhpFormulaeHandlerTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Foundation
import Testing

struct BrewPhpFormulaeHandlerTest {
    private let installedCommit = String(repeating: "a", count: 40)
    private let availableCommit = String(repeating: "b", count: 40)

    @Test func metadata_for_another_tap_cannot_trigger_a_reinstall() async throws {
        let info = """
        {"formulae":[{
          "name":"php@8.7", "full_name":"other/php/php@8.7", "pinned":false, "outdated":true, "revision":2,
          "versions":{"stable":"8.7.0"},
          "urls":{"stable":{"url":"https://www.php.net/distributions/php-8.7.0.tar.xz"}}
        }]}
        """
        let container = makeContainer(info: info)
        let items = await BrewPhpFormulaeHandler(container).loadPhpVersions(loadOutdated: false)
        let formula = try #require(items.first { $0.displayName == "PHP 8.7" })
        #expect(formula.name == "shivammathur/php/php@8.7")
        #expect(formula.updateCheck == .unknown)
        #expect(!formula.hasUpgrade)
    }

    @Test(arguments: [false, true])
    func main_formula_migration_uses_fresh_metadata_for_the_automatic_install_row(_ pinned: Bool) async throws {
        let info = """
        {"formulae":[{
          "name":"php", "full_name":"php", "pinned":\(pinned), "outdated":true, "revision":0,
          "versions":{"stable":"8.6.0"},
          "urls":{"stable":{"url":"https://www.php.net/distributions/php-8.6.0.tar.xz"}}
        }]}
        """
        let container = makeContainer(info: info)
        container.phpEnvs.homebrewPackage = HomebrewPackage(
            full_name: "php", aliases: [], installed: [],
            versions: HomebrewVersion(stable: "8.5.1", head: nil, bottle: true), linked_keg: nil
        )
        let items = await BrewPhpFormulaeHandler(container).loadPhpVersions(loadOutdated: true)
        let target = try #require(items.first { $0.displayName == "PHP 8.6" })
        #expect(target.hasUpgradedFormulaAlias == !pinned)
        #expect(!target.isInstalled)
        #expect(container.phpEnvs.brewPhpAlias == "8.5")
    }

    @Test(arguments: [false, true])
    func changed_nightly_uses_reinstall_and_respects_pins(_ pinned: Bool) async throws {
        let container = makeContainer(pinned: pinned)
        let handler = BrewPhpFormulaeHandler(container)
        let items = await handler.loadPhpVersions(loadOutdated: true)
        let formula = try #require(items.first { $0.displayName == "PHP 8.7" })

        #expect(formula.installedVersion == "8.7.0-dev")
        #expect(formula.prerelease == true)
        #expect(formula.isPinned == pinned)
        #expect(formula.hasUpgrade == !pinned)
        #expect(formula.update == .reinstallSnapshot(installedCommit: installedCommit, availableCommit: availableCommit))
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [formula], installing: [])
        #expect(command.upgradeOperations == (pinned ? [] : ["reinstall shivammathur/php/php@8.7"]))
        #expect(!handler.formulae.updateCheckFailed)
        try await command.upgradePackages { _ in }
        let installed = try container.filesystem.getStringFromFile("/opt/homebrew/opt/php@8.7/.brew/php@8.7.rb")
        #expect(installed.contains(pinned ? installedCommit : availableCommit))
        let refreshed = await handler.loadPhpVersions(loadOutdated: false)
        let refreshedFormula = try #require(refreshed.first { $0.displayName == "PHP 8.7" })
        #expect(refreshedFormula.isPinned == pinned)
        #expect(!refreshedFormula.hasUpgrade)
        if !pinned {
            #expect(refreshedFormula.updateCheck == .current)
        }
    }

    @Test func regular_revision_upgrades_and_nightly_reinstalls_are_both_scheduled() {
        let container = makeContainer()
        let normal = BrewPhpFormula(
            container, name: "php@8.5", displayName: "PHP 8.5", installedVersion: "8.5.1",
            updateCheck: .available(.upgrade(version: "8.5.1_1"))
        )
        let nightly = BrewPhpFormula(
            container, name: "shivammathur/php/php@8.7", displayName: "PHP 8.7", installedVersion: "8.7.0-dev",
            updateCheck: .available(.reinstallSnapshot(installedCommit: installedCommit, availableCommit: availableCommit))
        )
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [normal, nightly], installing: [])
        #expect(command.upgradeOperations == ["upgrade php@8.5", "reinstall shivammathur/php/php@8.7"])
    }

    @Test(arguments: ["8.7.0-dev", "8.7.0alpha1", "8.7.0beta2", "8.7.0RC5"])
    func installed_prerelease_remains_marked_until_replaced_with_stable(_ version: String) async throws {
        let container = makeContainer(installedVersion: version, stableAvailable: true)
        let handler = BrewPhpFormulaeHandler(container)
        var items = await handler.loadPhpVersions(loadOutdated: true)
        let formula = try #require(items.first { $0.displayName == "PHP 8.7" })
        #expect(formula.installedVersion == version)
        #expect(formula.prerelease == true)
        #expect(formula.update == .reinstallRelease(version: "8.7.0"))
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [formula], installing: [])
        #expect(command.upgradeOperations == ["reinstall shivammathur/php/php@8.7"])

        // The fake reinstall writes the release formula into the installed keg.
        try await command.upgradePackages { _ in }
        (container.command as! TestableCommand).updateOutputs([
            "/opt/homebrew/opt/php@8.7/bin/php-config --version": "8.7.0"
        ])
        container.phpEnvs.cachedPhpInstallations["8.7"] = await PhpInstallation.detect(container, "8.7")
        items = await handler.loadPhpVersions(loadOutdated: false)
        let stable = try #require(items.first { $0.displayName == "PHP 8.7" })
        #expect(stable.installedVersion == "8.7.0")
        #expect(stable.prerelease == false)
        #expect(stable.updateCheck == .current)
        #expect(!stable.hasUpgrade)
    }

    @Test func malformed_json_and_missing_build_metadata_do_not_mean_up_to_date() async throws {
        let container = makeContainer()
        try container.filesystem.remove("/opt/homebrew/opt/php@8.7/.brew/php@8.7.rb")
        let handler = BrewPhpFormulaeHandler(container)
        let items = await handler.loadPhpVersions(loadOutdated: true)
        #expect(try #require(items.first { $0.displayName == "PHP 8.7" }).updateCheck == .unknown)

        let broken = makeContainer(info: "not JSON")
        let brokenHandler = BrewPhpFormulaeHandler(broken)
        let unknown = await brokenHandler.loadPhpVersions(loadOutdated: true)
        #expect(brokenHandler.formulae.updateCheckFailed)
        #expect(!unknown.contains { $0.hasUpgrade })
        #expect(try #require(unknown.first { $0.displayName == "PHP 8.7" }).updateCheck == .unknown)
    }

    @Test func uninstalled_versions_get_their_badge_from_the_tap() async throws {
        let container = makeContainer()
        container.phpEnvs.cachedPhpInstallations = [:]
        let handler = BrewPhpFormulaeHandler(container)
        let items = await handler.loadPhpVersions(loadOutdated: false)
        let formula = try #require(items.first { $0.displayName == "PHP 8.7" })
        #expect(!formula.isInstalled)
        #expect(formula.prerelease == true)
    }

    @Test func stable_refresh_does_not_require_the_saved_formula_or_another_brew_update() async throws {
        let container = makeContainer(installedVersion: "8.7.0", stableAvailable: true)
        try container.filesystem.remove("/opt/homebrew/opt/php@8.7/.brew/php@8.7.rb")
        let handler = BrewPhpFormulaeHandler(container)
        let items = await handler.loadPhpVersions(loadOutdated: false)
        let formula = try #require(items.first { $0.displayName == "PHP 8.7" })
        #expect(formula.updateCheck == .current)
        #expect(formula.prerelease == false)
        #expect(!handler.formulae.updateCheckFailed)
    }

    @Test func failed_nightly_reinstall_remains_available_after_a_local_refresh() async throws {
        let container = makeContainer(reinstallExitCode: 1)
        let handler = BrewPhpFormulaeHandler(container)
        let items = await handler.loadPhpVersions(loadOutdated: false)
        let formula = try #require(items.first { $0.displayName == "PHP 8.7" })
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [formula], installing: [])
        do {
            try await command.upgradePackages { _ in }
            Issue.record("Expected the failed reinstall to stop the operation")
        } catch let error as BrewCommandError {
            #expect(error.log.contains { $0.contains("Simulated reinstall failure") })
        }
        let refreshed = await handler.loadPhpVersions(loadOutdated: false)
        let unchanged = try #require(refreshed.first { $0.displayName == "PHP 8.7" })
        #expect(unchanged.update == formula.update)
        #expect(unchanged.hasUpgrade)
        let installed = try container.filesystem.getStringFromFile("/opt/homebrew/opt/php@8.7/.brew/php@8.7.rb")
        #expect(installed.contains(installedCommit))
    }

    @Test func unsuccessful_metadata_command_is_not_accepted_even_with_valid_json() async {
        let container = makeContainer(infoExitCode: 1)
        let handler = BrewPhpFormulaeHandler(container)
        let items = await handler.loadPhpVersions(loadOutdated: false)
        #expect(handler.formulae.updateCheckFailed)
        #expect(items.allSatisfy { $0.updateCheck == .unknown })
    }

    private func makeContainer(
        pinned: Bool = false,
        installedVersion: String = "8.7.0-dev",
        stableAvailable: Bool = false,
        info: String? = nil,
        reinstallExitCode: Int32? = nil,
        infoExitCode: Int32? = nil
    ) -> Container {
        let sourceURL = stableAvailable
            ? "https://www.php.net/distributions/php-8.7.0.tar.xz"
            : "https://github.com/php/php-src/archive/\(availableCommit).tar.gz"
        let output = info ?? """
        {"formulae":[{
          "name":"php@8.7", "full_name":"shivammathur/php/php@8.7",
          "pinned":\(pinned), "outdated":false, "revision":1,
          "versions":{"stable":"8.7.0"}, "urls":{"stable":{"url":"\(sourceURL)"}}
        }]}
        """
        let container = Container.fake(
            shell: [
                "/opt/homebrew/bin/brew update >/dev/null && /opt/homebrew/bin/brew info --json=v2 --installed":
                    .init(items: [.instant(output)], exitCode: infoExitCode),
                "/opt/homebrew/bin/brew info --json=v2 --installed": .init(items: [.instant(output)], exitCode: infoExitCode),
                "/opt/homebrew/opt/php@8.7/bin/php --ini | grep -E -o '(/[^ ]+\\.ini)'": .instant(""),
                "export HOMEBREW_DOWNLOAD_CONCURRENCY=auto; export HOMEBREW_NO_INSTALL_UPGRADE=true; "
                    + "export HOMEBREW_NO_INSTALL_CLEANUP=true; export HOMEBREW_NO_ASK=true; "
                    + "/opt/homebrew/bin/brew reinstall shivammathur/php/php@8.7": .init(
                        items: [.instant(reinstallExitCode == nil ? "==> Pouring php@8.7" : "Simulated reinstall failure")],
                        transactions: reinstallExitCode == nil ? [
                            .write("  url \"\(sourceURL)\"\n  version \"8.7.0\"\n",
                                   to: "/opt/homebrew/opt/php@8.7/.brew/php@8.7.rb")
                        ] : [], exitCode: reinstallExitCode
                    )
            ],
            files: [
                "/opt/homebrew/opt/php@8.7/bin/php": .fake(.binary),
                "/opt/homebrew/opt/php@8.7/bin/php-config": .fake(.binary),
                "/opt/homebrew/opt/php@8.7/.brew/php@8.7.rb": .fake(.text,
                    "  url \"https://github.com/php/php-src/archive/\(installedCommit).tar.gz\"\n  version \"8.7.0\"\n"),
                "/opt/homebrew/opt/php@8.7/INSTALL_RECEIPT.json": .fake(.text,
                    #"{"source":{"tap":"shivammathur/php"}}"#),
                "/opt/homebrew/Library/Taps/shivammathur/homebrew-php/Formula/php@8.7.rb": .fake(.text,
                    "  url \"\(sourceURL)\"\n  version \"8.7.0\"\n")
            ],
            commands: [
                "/opt/homebrew/opt/php@8.7/bin/php-config --version": installedVersion,
                "/opt/homebrew/opt/php@8.7/bin/php -v": "PHP \(installedVersion)"
            ]
        )
        container.phpEnvs.brewPhpAlias = "8.5"
        container.phpEnvs.cachedPhpInstallations["8.7"] = PhpInstallation(
            container, "8.7", probe: .init(container, "8.7")
        )
        return container
    }
}
