//
//  FishShellIntegrationTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Foundation
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHPMON_TEST_FISH"] != nil,
                "Set PHPMON_TEST_FISH to a real fish executable to run integration tests"))
struct FishShellIntegrationTest {
    @Test(arguments: ["arm64", "x86_64"], [false, true])
    func onboarding_configuration_survives_a_new_shell(architecture: String, directoriesExist: Bool) throws {
        let fish = try #require(ProcessInfo.processInfo.environment["PHPMON_TEST_FISH"])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phpmon fish integration \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let container = makeOnboardingContainer(architecture: architecture, configuredShell: fish)
        let lines = ShellEnvironment(container).pathInstructionLines()
        let helper = root.appendingPathComponent(".config/phpmon/bin")
        let composer = root.appendingPathComponent(".composer/vendor/bin")
        if directoriesExist {
            for directory in [helper, composer] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }

        let marker = root.appendingPathComponent("custom bin with spaces").path
        let config = root.appendingPathComponent("config.fish")
        try (["set -gx PATH \(Self.quote(marker)) /usr/bin /bin"] + lines)
            .joined(separator: "\n").write(to: config, atomically: true, encoding: .utf8)

        // Only this fixture is sourced. Neither user nor system fish configuration is loaded.
        // A wrapper lets the production getPath method use the same isolated environment.
        let wrapper = root.appendingPathComponent("fish")
        let script = """
            #!/bin/sh
            exec /usr/bin/env -i HOME=\(Self.quote(root.path)) XDG_CONFIG_HOME=\(Self.quote(root.path)) PATH=/usr/bin:/bin \(Self.quote(fish)) --no-config --init-command \(Self.quote("source " + Self.quote(config.path))) "$@"
            """
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)

        let expected = [container.paths.binPath, composer.path, helper.path, marker, "/usr/bin", "/bin"]
        // Each call starts a new login/interactive shell and reloads config.fish.
        for _ in 0..<2 {
            let path = RealShell.getPath(shell: wrapper.path, timeout: 10)
            #expect(path.split(separator: ":").map(String.init) == expected)
        }

        // Passing the PATH to another process must preserve its colon-separated representation.
        let exportedPath = RealShell.getPath(
            shell: wrapper.path, timeout: 10,
            executeBeforeShellCommand: "/usr/bin/printenv PATH; exit"
        )
        #expect(exportedPath.split(separator: ":").map(String.init) == expected)
        if !directoriesExist {
            #expect(!FileManager.default.fileExists(atPath: composer.path))
            #expect(!FileManager.default.fileExists(atPath: helper.path))
        }
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
