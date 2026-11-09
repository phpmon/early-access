//
//  PhpFormulaMigrationTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Testing

struct PhpFormulaMigrationTest {
    @Test(arguments: ["php", "shivammathur/php/php"], ["7.4", "8.5"])
    func changing_the_main_formula_restores_the_old_series_before_other_updates(name: String, previous: String) async throws {
        let next = previous == "7.4" ? "8.0" : "8.6"
        let fixture = makeFixture(name: name, previous: previous, next: next)
        #expect(fixture.command.previousPhpVersion == previous)

        try await fixture.command.upgradePackages { _ in }

        for step in 0..<4 {
            #expect(fixture.container.filesystem.fileExists("/test/step-\(step)"))
        }
        #expect(fixture.container.filesystem.fileExists("/opt/homebrew/opt/php@\(previous)/bin/php"))
        #expect(fixture.container.phpEnvs.brewPhpAlias == next)
        #expect(fixture.command.previousPhpVersion == previous)
        let configuration = try fixture.container.filesystem.getStringFromFile("/opt/homebrew/etc/php/\(previous)/php.ini")
        #expect(configuration == "memory_limit = 512M")
    }

    @Test(arguments: 0..<4)
    func failed_upgrade_restore_or_reinstall_stops_the_remaining_batch(_ failedStep: Int) async throws {
        let fixture = makeFixture(failedStep: failedStep)
        do {
            try await fixture.command.upgradePackages { _ in }
            Issue.record("Expected the simulated Homebrew failure to stop the batch")
        } catch let error as BrewCommandError {
            #expect(error.log.contains { $0.contains("Failed step \(failedStep)") })
        }

        for step in 0..<4 {
            #expect(fixture.container.filesystem.fileExists("/test/step-\(step)") == (step < failedStep))
        }
        // Even a partial upgrade must not leave the app believing `php` is the previous series.
        #expect(fixture.container.phpEnvs.brewPhpAlias == (failedStep == 0 ? "8.5" : "8.6"))
        #expect(fixture.command.previousPhpVersion == "8.5")
        #expect(fixture.container.filesystem.fileExists("/opt/homebrew/opt/php@8.5/bin/php") == (failedStep != 1))
    }

    @Test func pinning_the_main_formula_skips_its_migration_but_keeps_other_updates() async throws {
        let fixture = makeFixture(pinned: true)
        try await fixture.command.upgradePackages { _ in }
        #expect(!fixture.container.filesystem.fileExists("/test/step-0"))
        #expect(!fixture.container.filesystem.fileExists("/test/step-1"))
        #expect(fixture.container.filesystem.fileExists("/test/step-2"))
        #expect(fixture.container.filesystem.fileExists("/test/step-3"))
        #expect(fixture.container.phpEnvs.brewPhpAlias == "8.5")
    }

    private func makeFixture(
        name: String = "shivammathur/php/php",
        previous: String = "8.5",
        next: String = "8.6",
        failedStep: Int? = nil,
        pinned: Bool = false
    ) -> Fixture {
        let operations = [
            "upgrade \(name)", "install \(name)@\(previous)",
            "upgrade php@8.2", "reinstall shivammathur/php/php@8.7"
        ]
        var shell: [String: BatchFakeShellOutput] = [
            "/opt/homebrew/bin/php --ini | grep -E -o '(/[^ ]+\\.ini)'": .instant("")
        ]
        for (index, operation) in operations.enumerated() {
            var transactions: [FakeShellTransaction] = [.write("done", to: "/test/step-\(index)")]
            if index == 0 {
                // Homebrew's main formula no longer provides the old series after upgrading.
                transactions.append(.remove("/opt/homebrew/opt/php@\(previous)/bin/php"))
            } else if index == 1 {
                transactions.append(.write("restored", to: "/opt/homebrew/opt/php@\(previous)/bin/php"))
            }
            let command = "export HOMEBREW_DOWNLOAD_CONCURRENCY=auto; export HOMEBREW_NO_INSTALL_UPGRADE=true; "
                + "export HOMEBREW_NO_INSTALL_CLEANUP=true; export HOMEBREW_NO_ASK=true; /opt/homebrew/bin/brew \(operation)"
            shell[command] = BatchFakeShellOutput(
                items: [.instant(index == failedStep ? "Failed step \(index)" : "==> Installing \(operation)")],
                transactions: index == failedStep ? [] : transactions,
                exitCode: index == failedStep ? 1 : 0
            )
        }
        let container = Container.fake(
            shell: shell,
            files: [
                "/opt/homebrew/bin/php-config": .fake(.binary),
                "/opt/homebrew/opt/php/bin/php-config": .fake(.binary),
                "/opt/homebrew/opt/php@\(previous)/bin/php": .fake(.binary),
                "/opt/homebrew/etc/php/\(previous)/php.ini": .fake(.text, "memory_limit = 512M")
            ],
            commands: [
                "/opt/homebrew/bin/php-config --version": "\(previous).1",
                "/opt/homebrew/opt/php/bin/php-config --version": "\(failedStep == 0 ? previous : next).1",
                "/opt/homebrew/bin/php -r echo ini_get('memory_limit');": "512M",
                "/opt/homebrew/bin/php -r echo ini_get('upload_max_filesize');": "2M",
                "/opt/homebrew/bin/php -r echo ini_get('post_max_size');": "8M"
            ]
        )
        container.phpEnvs.homebrewPackage = HomebrewPackage(
            full_name: name, aliases: [], installed: [],
            versions: HomebrewVersion(stable: "\(next).0", head: nil, bottle: true), linked_keg: nil
        )
        container.phpEnvs.brewPhpAlias = previous
        let migrating = BrewPhpFormula(
            container, name: name, displayName: "PHP \(previous)", installedVersion: "\(previous).1",
            updateCheck: .available(.upgrade(version: "\(next).0")), isPinned: pinned
        )
        let regular = BrewPhpFormula(
            container, name: "php@8.2", displayName: "PHP 8.2", installedVersion: "8.2.1",
            updateCheck: .available(.upgrade(version: "8.2.2"))
        )
        let nightly = BrewPhpFormula(
            container, name: "shivammathur/php/php@8.7", displayName: "PHP 8.7", installedVersion: "8.7.0-dev",
            updateCheck: .available(.reinstallSnapshot(installedCommit: "old", availableCommit: "new"))
        )
        let command = ModifyPhpVersionCommand(
            container, title: "Test", upgrading: [regular, nightly, migrating], installing: []
        )
        return Fixture(container: container, command: command)
    }

    private struct Fixture {
        let container: Container
        let command: ModifyPhpVersionCommand
    }
}
