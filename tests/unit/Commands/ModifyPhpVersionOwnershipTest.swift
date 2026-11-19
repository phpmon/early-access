//
//  ModifyPhpVersionOwnershipTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Testing

@MainActor
struct ModifyPhpVersionOwnershipTest {
    @MainActor final class Recorder {
        var requests: [Set<String>] = []
    }

    @Test func ownership_is_restored_for_replaced_versions_before_homebrew_runs() async throws {
        let container = Container.fake()
        let upgrade = BrewPhpFormula(
            container, name: "php@8.4", displayName: "PHP 8.4", installedVersion: "8.4.0",
            updateCheck: .available(.upgrade(version: "8.4.1"))
        )
        let pinned = BrewPhpFormula(
            container, name: "php@8.3", displayName: "PHP 8.3", installedVersion: "8.3.0",
            updateCheck: .available(.upgrade(version: "8.3.1")), isPinned: true
        )
        let install = BrewPhpFormula(container, name: "php@8.7", displayName: "PHP 8.7", installedVersion: nil)
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [upgrade, pinned], installing: [install])
        let recorder = Recorder()
        command.restoreOwnership = { versions in
            recorder.requests.append(versions)
            throw AdminPrivilegeError(kind: .userDenied)
        }

        await #expect(throws: AdminPrivilegeError(kind: .userDenied)) {
            try await command.execute(shell: container.shell) { _ in }
        }
        // Pinned versions are not upgraded, and fresh installs have nothing to give back.
        #expect(recorder.requests == [["8.4"]])
        #expect(!container.commandTracker.commands.contains { $0.command.contains("/opt/homebrew/bin/brew") })
    }
}
