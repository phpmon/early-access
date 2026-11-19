//
//  PrepareValetPhpSupportOwnershipTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Testing
import Foundation

extension PrepareValetPhpSupportTest {
    @Test(arguments: [2, 3])
    func unknown_layout_uses_the_installed_valet_majors_support_range(_ major: Int) async throws {
        let original = "<?php // Unrecognized support list"
        let container = makeContainer(current: "\(major).0.0", content: original)
        let supported = major == 2 ? "8.2" : "8.4"
        let newer = major == 2 ? "8.3" : "8.5"
        try await PrepareValetPhpSupportCommand(container, versions: [supported]).execute(shell: container.shell) { _ in }
        do {
            try await PrepareValetPhpSupportCommand(container, versions: [supported, newer], approval: { _ in true })
                .execute(shell: container.shell) { _ in }
            Issue.record("Expected the unrecognized list to stop PHP \(newer)")
        } catch let error as BrewCommandError {
            // The message names only the unlisted version, the entry to add and the file to edit.
            #expect(error.error == ValetPhpSupportError.unrecognizedSourceMessage(versions: [newer], file: sourcePath))
            #expect(error.error.contains("'php@\(newer)'"))
            #expect(error.error.contains(sourcePath))
            #expect(!error.error.contains("PHP \(supported)"))
        }
        #expect(try container.filesystem.getStringFromFile(sourcePath) == original)
    }

    @Test(arguments: ["otherInstallation", "oldLayout", "noisyVersion", "changedFile", "corruptRecord"])
    func supported_php_does_not_require_a_patchable_valet(_ setup: String) async throws {
        let container = makeContainer(
            content: setup == "oldLayout" ? "<?php // Older Valet layout" : source(),
            installationMismatch: setup == "otherInstallation"
        )
        if setup == "noisyVersion" {
            let shell = container.shell as! TestableShell
            shell.expectations["'/opt/homebrew/bin/valet' --version"] = .instant("PHP Deprecated: notice\nLaravel Valet 4.12.0")
        } else if setup == "changedFile" {
            try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true })
                .execute(shell: container.shell) { _ in }
            let changed = try container.filesystem.getStringFromFile(sourcePath) + "\n// User edit"
            try container.filesystem.writeAtomicallyToFile(sourcePath, content: changed)
        } else if setup == "corruptRecord" {
            try container.filesystem.writeAtomicallyToFile(ValetPhpSupportEdits(container: container).path, content: "{")
        }
        let original = try container.filesystem.getStringFromFile(sourcePath)
        try await PrepareValetPhpSupportCommand(container, versions: ["8.4"]).execute(shell: container.shell) { _ in }
        #expect(try container.filesystem.getStringFromFile(sourcePath) == original)
        await #expect(throws: BrewCommandError.self) {
            try await PrepareValetPhpSupportCommand(container, versions: ["8.4", "8.8"], approval: { _ in true })
                .execute(shell: container.shell) { _ in }
        }
        #expect(try container.filesystem.getStringFromFile(sourcePath) == original)
    }

    @Test(arguments: [false, true])
    func an_external_valet_update_offers_installed_temporary_support_again(_ adds86: Bool) async throws {
        let upstream = adds86 ? source(versions: ["8.6", "8.5", "8.4"]) : source()
        let container = makeContainer()
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true })
            .execute(shell: container.shell) { _ in }
        try container.filesystem.writeAtomicallyToFile("/opt/homebrew/opt/php@8.7/bin/php", content: "installed")
        try updateValetExternally(container, to: "4.13.0", source: upstream)
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6"], approval: { change in
            #expect(change.versions == (adds86 ? ["8.7"] : ["8.7", "8.6"]))
            return true
        }).execute(shell: container.shell) { _ in }
        let content = try container.filesystem.getStringFromFile(sourcePath)
        #expect(try ValetPhpVersionList(content).versions.isSuperset(of: ["8.6", "8.7"]))
    }

    @Test(arguments: [false, true], [false, true])
    func updating_valet_preserves_temporary_support_only_for_still_installed_php(stillInstalled: Bool, upstreamAddsSupport: Bool) async throws {
        let upstream = source(versions: upstreamAddsSupport ? ["8.7", "8.6", "8.5", "8.4"] : ["8.5", "8.4"])
        let container = makeContainer()
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true })
            .execute(shell: container.shell) { _ in }
        if stillInstalled {
            try container.filesystem.writeAtomicallyToFile("/opt/homebrew/opt/php@8.7/bin/php", content: "installed")
        }
        try updateValetExternally(container, to: "4.13.0", source: upstream)
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6"], approval: { _ in true })
            .execute(shell: container.shell) { _ in }
        let content = try container.filesystem.getStringFromFile(sourcePath)
        let versions = try ValetPhpVersionList(content).versions
        #expect(versions.contains("8.6"))
        #expect(versions.contains("8.7") == (stillInstalled || upstreamAddsSupport))
        let owned = try ValetPhpSupportEdits(container: container).ownedVersions(
            at: sourcePath, valetVersion: "4.13.0", content: content
        )
        #expect(owned == (upstreamAddsSupport ? [] : (stillInstalled ? ["8.6", "8.7"] : ["8.6"])))
        if stillInstalled {
            try container.filesystem.remove("/opt/homebrew/opt/php@8.7/bin/php")
        }
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7"]).removeOwnedSupport(shell: container.shell)
        #expect(try container.filesystem.getStringFromFile(sourcePath) == upstream)
    }

    @Test func failed_partial_install_cleans_up_only_new_entries_without_an_installed_php() async throws {
        let container = makeContainer()
        let existing = PrepareValetPhpSupportCommand(container, versions: ["8.6"], approval: { _ in true })
        try await existing.execute(shell: container.shell) { _ in }

        let batch = PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7", "8.8"], approval: { _ in true })
        try await batch.execute(shell: container.shell) { _ in }
        #expect(batch.addedVersions == ["8.7", "8.8"])
        try container.filesystem.writeAtomicallyToFile("/opt/homebrew/opt/php@8.7/bin/php", content: "installed")
        try await batch.removeOwnedSupport(shell: container.shell, for: batch.addedVersions)

        let remaining = try ValetPhpVersionList(container.filesystem.getStringFromFile(sourcePath))
        #expect(remaining.versions == ["8.4", "8.5", "8.6", "8.7"])
    }

    @Test func rolled_back_second_patch_does_not_lose_ownership_of_the_first_patch() async throws {
        let container = makeContainer()
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true })
            .execute(shell: container.shell) { _ in }
        let original = try container.filesystem.getStringFromFile(sourcePath)
        let shell = container.shell as! TestableShell
        let lint = "'/opt/homebrew/bin/php' -l '\(sourcePath)'"
        shell.expectations[lint] = .init(items: [.instant("Parse error")], exitCode: 1)
        do {
            try await PrepareValetPhpSupportCommand(container, versions: ["8.6"], approval: { _ in true })
                .execute(shell: container.shell) { _ in }
            Issue.record("Expected the second patch's syntax check to fail")
        } catch is BrewCommandError {
            #expect(try container.filesystem.getStringFromFile(sourcePath) == original)
            #expect(try ValetPhpSupportEdits(container: container).ownedVersions(
                at: sourcePath, valetVersion: "4.12.0", content: original
            ) == ["8.7"])
        }
        shell.expectations[lint] = .instant("No syntax errors detected")
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"]).removeOwnedSupport(shell: container.shell)
        #expect(try container.filesystem.getStringFromFile(sourcePath) == source())
    }

    @Test(arguments: [["8.7", "8.6"], ["8.6", "8.7"]])
    func temporary_support_can_be_added_and_removed_in_either_installation_order(_ order: [String]) async throws {
        let container = makeContainer()
        for version in order {
            try await PrepareValetPhpSupportCommand(container, versions: [version], approval: { _ in true })
                .execute(shell: container.shell) { _ in }
        }
        let content = try container.filesystem.getStringFromFile(sourcePath)
        #expect(try ValetPhpVersionList(content).versions.isSuperset(of: ["8.6", "8.7"]))
        let edits = ValetPhpSupportEdits(container: container)
        #expect(try edits.ownedVersions(at: sourcePath, valetVersion: "4.12.0", content: content) == ["8.6", "8.7"])
        for version in order {
            try await PrepareValetPhpSupportCommand(container, versions: [version]).removeOwnedSupport(shell: container.shell)
        }
        #expect(try container.filesystem.getStringFromFile(sourcePath) == source())
    }

    @Test func older_unsupported_php_never_offers_a_support_patch() async throws {
        let container = makeContainer()
        do {
            try await PrepareValetPhpSupportCommand(container, versions: ["7.0"], approval: { _ in
                Issue.record("Older unsupported PHP versions must not offer support changes")
                return false
            }).execute(shell: container.shell) { _ in }
            Issue.record("Expected the older unsupported PHP version to be rejected")
        } catch is BrewCommandError {
            #expect(try container.filesystem.getStringFromFile(sourcePath) == source())
        }
    }

    @Test func missing_or_declined_permission_leaves_valet_unchanged() async throws {
        let container = makeContainer(latest: "4.13.0")
        do {
            try await PrepareValetPhpSupportCommand(container, versions: ["8.7"]).execute(shell: container.shell) { _ in }
            Issue.record("Expected missing approval to cancel the operation")
        } catch ValetPhpSupportError.cancelled {
            #expect(try container.filesystem.getStringFromFile(sourcePath) == source())
            #expect(!container.filesystem.fileExists(ValetPhpSupportEdits(container: container).path))
            #expect(container.valet.version?.text == "4.12.0")
        }
    }

    @Test func recorded_additions_are_removed_individually_across_command_instances() async throws {
        let container = makeContainer()
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7"], approval: { _ in true })
            .execute(shell: container.shell) { _ in }
        #expect(container.filesystem.fileExists(ValetPhpSupportEdits(container: container).path))
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"]).removeOwnedSupport(shell: container.shell)
        var content = try container.filesystem.getStringFromFile(sourcePath)
        #expect(try ValetPhpVersionList(content).versions == ["8.6", "8.5", "8.4"])
        #expect(content.contains("const LIMITED_PHP_VERSIONS = ['php@7.1'];"))
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6"]).removeOwnedSupport(shell: container.shell)
        content = try container.filesystem.getStringFromFile(sourcePath)
        #expect(content == source())
    }

    @Test func untracked_entries_are_never_removed() async throws {
        let original = source(versions: ["8.7", "8.5"])
        let container = makeContainer(content: original)
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"]).removeOwnedSupport(shell: container.shell)
        #expect(try container.filesystem.getStringFromFile(sourcePath) == original)
    }

    @Test func a_new_patch_does_not_take_ownership_of_an_existing_entry() async throws {
        let original = source(versions: ["8.6", "8.5"])
        let container = makeContainer(content: original)
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7"], approval: { _ in true })
            .execute(shell: container.shell) { _ in }
        try await PrepareValetPhpSupportCommand(container, versions: ["8.6", "8.7"]).removeOwnedSupport(shell: container.shell)
        #expect(try container.filesystem.getStringFromFile(sourcePath) == original)
    }

    @Test func removing_an_entry_does_not_edit_other_valet_arrays() throws {
        let original = source(versions: ["8.7", "8.5"]).replacing(
            "const LIMITED_PHP_VERSIONS = ['php@7.1'];",
            with: "const LIMITED_PHP_VERSIONS = [\n        'php@8.7',\n    ];"
        )
        let updated = try ValetPhpVersionList(original).removing(["8.7"])
        #expect(try ValetPhpVersionList(updated).versions == ["8.5"])
        #expect(updated.contains("const LIMITED_PHP_VERSIONS = [\n        'php@8.7',\n    ];"))
    }

    @Test func still_installed_php_keeps_its_owned_valet_entry() async throws {
        let container = makeContainer()
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true })
            .execute(shell: container.shell) { _ in }
        try container.filesystem.writeAtomicallyToFile("/opt/homebrew/opt/php@8.7/bin/php", content: "installed")
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"]).removeOwnedSupport(shell: container.shell)
        let content = try container.filesystem.getStringFromFile(sourcePath)
        #expect(try ValetPhpVersionList(content).versions.contains("8.7"))
    }

    @Test func external_edits_prevent_automatic_removal() async throws {
        let container = makeContainer()
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true })
            .execute(shell: container.shell) { _ in }
        let content = try container.filesystem.getStringFromFile(sourcePath) + "\n// User change\n"
        try container.filesystem.writeAtomicallyToFile(sourcePath, content: content)
        do {
            try await PrepareValetPhpSupportCommand(container, versions: ["8.7"]).removeOwnedSupport(shell: container.shell)
            Issue.record("Expected unknown ownership after an external edit")
        } catch ValetPhpSupportError.ownershipChanged {
            #expect(try container.filesystem.getStringFromFile(sourcePath) == content)
        }
    }

    @Test func a_new_valet_release_owns_its_own_entries_even_if_the_file_is_identical() async throws {
        let container = makeContainer()
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true })
            .execute(shell: container.shell) { _ in }
        let content = try container.filesystem.getStringFromFile(sourcePath)
        (container.shell as! TestableShell).expectations["'/opt/homebrew/bin/valet' --version"] = .instant("Laravel Valet 4.13.0")
        try await PrepareValetPhpSupportCommand(container, versions: ["8.7"]).removeOwnedSupport(shell: container.shell)
        #expect(try container.filesystem.getStringFromFile(sourcePath) == content)
    }

    @Test func interrupted_or_rolled_back_edits_preserve_previous_ownership() async throws {
        let container = makeContainer()
        let edits = ValetPhpSupportEdits(container: container)
        let initial = source()
        let with86 = try ValetPhpVersionList(initial).adding(["8.6"]).content
        let withBoth = try ValetPhpVersionList(with86).adding(["8.7"]).content
        try edits.record(file: sourcePath, valetVersion: "4.12.0", before: (with86, ["8.6"]), after: (withBoth, ["8.6", "8.7"]))
        #expect(try edits.ownedVersions(at: sourcePath, valetVersion: "4.12.0", content: with86) == ["8.6"])
        #expect(try edits.ownedVersions(at: sourcePath, valetVersion: "4.12.0", content: withBoth) == ["8.6", "8.7"])
    }

    @Test func corrupt_tracking_data_prevents_a_new_patch() async throws {
        let container = makeContainer()
        try container.filesystem.writeAtomicallyToFile(ValetPhpSupportEdits(container: container).path, content: "invalid JSON")
        do {
            try await PrepareValetPhpSupportCommand(container, versions: ["8.7"], approval: { _ in true })
                .execute(shell: container.shell) { _ in }
            Issue.record("Expected corrupt ownership data to stop the patch")
        } catch is BrewCommandError {
            #expect(try container.filesystem.getStringFromFile(sourcePath) == source())
        }
    }
}
