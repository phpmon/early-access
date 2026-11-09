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

    @Test(arguments: [false, true])
    func update_is_checked_again_before_deciding_whether_to_patch(_ updateAddsSupport: Bool) async throws {
        let updated = source(versions: updateAddsSupport ? ["8.7", "8.6", "8.5"] : ["8.5"]) + "\n// Installed by Composer update\n"
        let container = makeContainer(current: "4.11.0", updatedSource: updated)
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7"], approval: { _ in true }).execute(shell: container.shell) { _ in }
        let content = try container.filesystem.getStringFromFile(sourcePath)
        #expect(try ValetPhpVersionList(content).versions.isSuperset(of: ["8.6", "8.7"]))
        #expect(content.contains("// Installed by Composer update"))
        #expect(container.valet.version?.text == "4.12.0")
        if updateAddsSupport {
            #expect(content == updated)
        }
    }

    @Test func already_supported_versions_work_without_network_access() async throws {
        let original = source(versions: ["8.7", "8.6", "8.5"])
        let container = makeContainer(content: original, networkStatus: 503)
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7"]).execute(shell: container.shell) { _ in }
        #expect(try container.filesystem.getStringFromFile(sourcePath) == original)
    }

    @Test func failed_valet_preparation_stops_the_php_manager_before_homebrew_runs() async throws {
        let container = makeContainer(networkStatus: 503)
        let formula = BrewPhpFormula(
            container, name: "shivammathur/php/php@8.7", displayName: "PHP 8.7", installedVersion: nil, releaseStatus: .prerelease(nil)
        )
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [], installing: [formula])
        do {
            try await command.execute(shell: container.shell) { _ in }
            Issue.record("Expected Valet's failed update check to prevent the PHP installation")
        } catch is BrewCommandError {
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
    func manager_keeps_future_series_but_does_not_expand_legacy_valet_support(_ major: Int) {
        let container = Container.fake()
        container.valet.version = VersionNumber(major: major, minor: 0, patch: 0)
        let older = BrewPhpFormula(container, name: "php@5.6", displayName: "PHP 5.6", installedVersion: nil)
        let future = BrewPhpFormula(container, name: "php@8.7", displayName: "PHP 8.7", installedVersion: nil, releaseStatus: .prerelease(nil))
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [], installing: [older, future])
        #expect(command.requestedPhpVersions == ["8.7"])
    }

    @Test(arguments: [Failure.network, .composer, .constrained, .majorUpgrade, .installationMismatch, .syntax,
                      .unfamiliarSource, .readOnly, .prereleaseValet])
    func failed_preconditions_or_validation_never_leave_a_patched_list(_ failure: Failure) async throws {
        let original = failure == .unfamiliarSource ? source().replacing("const SUPPORTED_PHP_VERSIONS", with: "const OTHER_VERSIONS") : source()
        let container = makeContainer(
            current: failure == .prereleaseValet ? "4.12.0-dev"
                : (failure == .composer || failure == .constrained ? "4.11.0" : "4.12.0"),
            latest: failure == .majorUpgrade ? "5.0.0" : "4.12.0",
            content: original,
            updatedVersion: failure == .constrained ? "4.11.0" : "4.12.0",
            updateExitCode: failure == .composer ? 1 : 0,
            lintExitCode: failure == .syntax ? 1 : 0,
            networkStatus: failure == .network ? 503 : 200,
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
        latest: String = "4.12.0",
        content: String? = nil,
        updatedSource: String? = nil,
        updatedVersion: String = "4.12.0",
        updateExitCode: Int32 = 0,
        lintExitCode: Int32 = 0,
        networkStatus: Int = 200,
        installationMismatch: Bool = false,
        sourceReadOnly: Bool = false,
        changedDuringVersionCheck: String? = nil,
        changedDuringLint: String? = nil
    ) -> Container {
        let versionCommand = "'/opt/homebrew/bin/valet' --version"
        var updateTransactions: [FakeShellTransaction] = [
            .shell(versionCommand, .instant("Laravel Valet \(updatedVersion)"))
        ]
        if let updatedSource { updateTransactions.append(.write(updatedSource, to: sourcePath)) }
        let container = Container.fake(
            shell: [
                "'/opt/homebrew/bin/composer' global config vendor-dir --absolute": .instant("\(root)/../.."),
                versionCommand: .init(items: [.instant("Laravel Valet \(current)")],
                    transactions: changedDuringVersionCheck.map { [.write($0, to: sourcePath)] } ?? []),
                "'/opt/homebrew/bin/composer' global update laravel/valet --with-all-dependencies --no-interaction":
                    .init(items: [.instant("Composer update")], transactions: updateExitCode == 0 ? updateTransactions : [], exitCode: updateExitCode),
                "'/opt/homebrew/bin/php' -l '\(sourcePath)'": .init(
                    items: [.instant(lintExitCode == 0 ? "No syntax errors detected" : "Parse error")],
                    transactions: changedDuringLint.map { [.write($0, to: sourcePath)] } ?? [], exitCode: lintExitCode
                )
            ],
            files: [
                "/opt/homebrew/bin/composer": .fake(.binary),
                "/opt/homebrew/bin/valet": .fake(.symlink, installationMismatch ? "/different/valet" : "\(root)/valet"),
                "/different/valet": .fake(.binary),
                "\(root)/valet": .fake(.binary),
                sourcePath: .fake(.text, content ?? source(), readOnly: sourceReadOnly)
            ],
            getResponses: [URL(string: "https://repo.packagist.org/p2/laravel/valet.json")!: .init(
                statusCode: networkStatus, headers: [:],
                text: "{\"packages\":{\"laravel/valet\":[{\"version\":\"v\(latest)\",\"version_normalized\":\"\(latest).0\"}]}}", duration: 0
            )]
        )
        container.valet.installed = true
        return container
    }

    nonisolated enum Failure: Sendable {
        case network, composer, constrained, majorUpgrade, installationMismatch, syntax, unfamiliarSource, readOnly, prereleaseValet
    }
}
