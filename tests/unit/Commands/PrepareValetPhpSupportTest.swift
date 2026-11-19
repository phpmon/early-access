//
//  PrepareValetPhpSupportTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Foundation
import Testing

struct PrepareValetPhpSupportTest {
    private let root = "/Users/fake/Composer Home/vendor/laravel/valet"

    @Test func latest_valet_gets_only_the_requested_new_versions_and_repeated_runs_do_nothing() async throws {
        let container = makeContainer()
        let command = PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7"], approval: { _ in true })
        try await command.execute(shell: container.shell) { _ in }
        let expected = source().replacing("        'php',\n", with: "        'php',\n        'php@8.7',\n        'php@8.6',\n")
        #expect(try container.filesystem.getStringFromFile(sourcePath) == expected)
        try await command.execute(shell: container.shell) { _ in }
        #expect(try container.filesystem.getStringFromFile(sourcePath) == expected)
    }

    @Test(arguments: ["4.12.0", "4.13.0"])
    func a_newer_valet_is_mentioned_in_the_prompt_but_never_installed(_ latest: String) async throws {
        let container = makeContainer(latest: latest)
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { change in
            #expect(change.versions == ["8.7"])
            #expect(change.newerValetVersion == (latest == "4.13.0" ? "4.13.0" : nil))
            #expect(change.message.contains("phpman.valet.add.newer_valet".localized("4.13.0", "8.7")) == (latest == "4.13.0"))
            return true
        }).execute(shell: container.shell) { _ in }
        #expect(container.valet.version?.text == "4.12.0")
        #expect(try ValetPhpVersionList(container.filesystem.getStringFromFile(sourcePath)).versions.contains("8.7"))
    }

    @Test func already_supported_versions_need_no_changes() async throws {
        let original = source(versions: ["8.7", "8.6", "8.5"])
        let container = makeContainer(content: original)
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7"]).execute(shell: container.shell) { _ in }
        #expect(try container.filesystem.getStringFromFile(sourcePath) == original)
    }

    @Test func failed_valet_preparation_stops_the_php_manager_before_homebrew_runs() async throws {
        let container = makeContainer(sourceReadOnly: true)
        let formula = BrewPhpFormula(
            container, name: "shivammathur/php/php@8.7", displayName: "PHP 8.7", installedVersion: nil, releaseStatus: .prerelease(nil)
        )
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [], installing: [formula])
        command.approveValetChange = { _ in true }
        do {
            try await command.execute(shell: container.shell) { _ in }
            Issue.record("Expected the read-only Valet file to prevent the PHP installation")
        } catch let error as ValetSupportPreparationError {
            #expect(error.versions == ["8.7"])
            #expect(error.detail == "phpman.valet.errors.source_not_writable".localized)
            #expect(try container.filesystem.getStringFromFile(sourcePath) == source())
            #expect(!container.filesystem.fileExists("/opt/homebrew/opt/php@8.7/bin/php"))
        }
    }

    @Test func absent_valet_requires_no_commands_or_network() async throws {
        let container = Container.fake()
        container.valet.installed = false
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true }).execute(shell: container.shell) { _ in }
    }

    @Test(arguments: [3, 4])
    func the_series_moving_to_the_php_formula_is_left_to_isolation(_ major: Int) {
        let container = Container.fake()
        container.valet.version = VersionNumber(major: major, minor: 0, patch: 0)
        let php = BrewPhpFormula(
            container, name: "php", displayName: "PHP 8.4", installedVersion: "8.4.0",
            updateCheck: .available(.upgrade(version: "8.5.0"))
        )
        let other = BrewPhpFormula(container, name: "php@8.6", displayName: "PHP 8.6", installedVersion: nil)
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [php], installing: [other])
        // Valet accepts PHP 8.5 through `php`. Valet 3's built-in mapping ends at PHP 8.4, so it still needs an entry there.
        #expect(command.requestedPhpVersions == (major == 4 ? ["8.4", "8.6"] : ["8.4", "8.5", "8.6"]))
    }

    @Test(arguments: [3, 4])
    func manager_keeps_future_series_but_does_not_expand_legacy_valet_support(_ major: Int) {
        let container = Container.fake()
        container.valet.version = VersionNumber(major: major, minor: 0, patch: 0)
        let older = BrewPhpFormula(container, name: "php@5.6", displayName: "PHP 5.6", installedVersion: nil)
        let future = BrewPhpFormula(container, name: "php@8.7", displayName: "PHP 8.7", installedVersion: nil, releaseStatus: .prerelease(nil))
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [], installing: [older, future])
        #expect(command.requestedPhpVersions == ["8.7"])
    }

    @Test(arguments: [Failure.installationMismatch, .syntax, .unfamiliarSource, .readOnly, .prereleaseValet])
    func failed_preconditions_or_validation_never_leave_a_patched_list(_ failure: Failure) async throws {
        let original = failure == .unfamiliarSource ? source().replacing("const SUPPORTED_PHP_VERSIONS", with: "const OTHER_VERSIONS") : source()
        let container = makeContainer(
            current: failure == .prereleaseValet ? "4.12.0-dev" : "4.12.0",
            content: original,
            lintExitCode: failure == .syntax ? 1 : 0,
            installationMismatch: failure == .installationMismatch,
            sourceReadOnly: failure == .readOnly
        )
        do {
            try await PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7"], approval: { _ in true }).execute(shell: container.shell) { _ in }
            Issue.record("Expected Valet preparation to fail for \(failure)")
        } catch is BrewCommandError {
            #expect(try container.filesystem.getStringFromFile(sourcePath) == original)
        }
    }

    @Test(arguments: [false, true])
    func concurrent_changes_are_preserved_before_writing_or_during_rollback(_ duringLint: Bool) async throws {
        let concurrent = source() + "\n// Concurrent Composer update\n"
        let container = makeContainer(
            lintExitCode: duringLint ? 1 : 0,
            changedDuringVersionCheck: duringLint ? nil : concurrent,
            changedDuringLint: duringLint ? concurrent : nil
        )
        do {
            try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true }).execute(shell: container.shell) { _ in }
            Issue.record("Expected the concurrent update to stop preparation")
        } catch is BrewCommandError {
            #expect(try container.filesystem.getStringFromFile(sourcePath) == concurrent)
        }
    }

    @Test func support_eligibility_keeps_existing_entries_and_uses_the_official_boundary() throws {
        let list = try ValetPhpVersionList(source(versions: ["8.7", "8.5", "8.4"]))
        #expect(list.canSupport("8.4", temporaryVersions: ["8.7"]))
        #expect(list.canSupport("8.7", temporaryVersions: ["8.7"]))
        #expect(list.canSupport("8.6", temporaryVersions: ["8.7"]))
        #expect(!list.canSupport("8.6"))
        #expect(!list.canSupport("8x8", temporaryVersions: ["8.7"]))
        #expect(!list.canSupport("7.0", temporaryVersions: ["8.7"]))
        #expect(!list.canSupport("8.8'; bad() //", temporaryVersions: ["8.7"]))
        #expect(!list.canSupport("8.8", temporaryVersions: list.versions))
    }

    @Test func parser_rejects_expressions_duplicate_declarations_and_older_unsupported_series() throws {
        for content in [
            source() + source(),
            source().replacing("'php@8.5',", with: "getVersion(),"),
            source().replacing("        'php',", with: "        'php',\n        'php',")
        ] {
            #expect(throws: ValetPhpSupportError.self) { try ValetPhpVersionList(content) }
        }
        let list = try ValetPhpVersionList(source())
        #expect(throws: ValetPhpSupportError.self) { try list.adding(["7.0"]) }
        #expect(throws: ValetPhpSupportError.self) { try list.adding(["8.7'; bad() //"]) }
    }

    var sourcePath: String { "\(root)/cli/Valet/Brew.php" }

    func source(versions: [String] = ["8.5", "8.4"]) -> String {
        """
        <?php
        namespace Valet;
        class Brew
        {
            const SUPPORTED_PHP_VERSIONS = [
                'php',
        \(versions.map { "        'php@\($0)'," }.joined(separator: "\n"))
            ];
            const LATEST_PHP_VERSION = 'php@8.5';
            const LIMITED_PHP_VERSIONS = ['php@7.1'];
        }
        """
    }

    func makeContainer(
        current: String = "4.12.0",
        latest: String? = nil,
        content: String? = nil,
        lintExitCode: Int32 = 0,
        installationMismatch: Bool = false,
        sourceReadOnly: Bool = false,
        changedDuringVersionCheck: String? = nil,
        changedDuringLint: String? = nil
    ) -> Container {
        let versionCommand = "'/opt/homebrew/bin/valet' --version"
        let container = Container.fake(
            shell: [
                versionCommand: .init(items: [.instant("Laravel Valet \(current)")],
                    transactions: changedDuringVersionCheck.map { [.write($0, to: sourcePath)] } ?? []),
                "'/opt/homebrew/bin/php' -l '\(sourcePath)'": .init(
                    items: [.instant(lintExitCode == 0 ? "No syntax errors detected" : "Parse error")],
                    transactions: changedDuringLint.map { [.write($0, to: sourcePath)] } ?? [], exitCode: lintExitCode
                )
            ],
            files: [
                "/opt/homebrew/bin/valet": .fake(.symlink, installationMismatch ? "/different/valet" : "\(root)/valet"),
                "/different/valet": .fake(.binary),
                "\(root)/valet": .fake(.binary),
                sourcePath: .fake(.text, content ?? source(), readOnly: sourceReadOnly)
            ]
        )
        container.valet.installed = true
        container.valet.latestVersion = latest.flatMap { try? VersionNumber.parse($0) }
        return container
    }

    /// Simulate the user updating Valet outside PHP Monitor, which replaces `Brew.php`.
    func updateValetExternally(_ container: Container, to version: String, source: String) throws {
        try container.filesystem.writeAtomicallyToFile(sourcePath, content: source)
        (container.shell as! TestableShell).expectations["'/opt/homebrew/bin/valet' --version"] = .instant("Laravel Valet \(version)")
    }

    nonisolated enum Failure: Sendable {
        case installationMismatch, syntax, unfamiliarSource, readOnly, prereleaseValet
    }
}
