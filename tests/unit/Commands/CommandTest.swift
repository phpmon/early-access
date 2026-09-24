//
//  CommandTest.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 13/02/2021.
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Testing
import Foundation

struct CommandTest {
    @Test(arguments: [
        OutputCase(script: "printf 'first\\n\\nsecond\\n'", expected: "first\n\nsecond\n"),
        OutputCase(script: "printf 'first\\n\\nsecond\\n'", expected: "first\nsecond", trimNewlines: true),
        OutputCase(script: "printf out; printf err >&2", expected: "out"),
        OutputCase(script: "printf out; printf err >&2", expected: "outerr", withStandardError: true),
        OutputCase(script: "printf failure; exit 7", expected: "failure", withStandardError: true),
        // Preserve the existing sentinel when readToEnd() returns nil at immediate EOF.
        OutputCase(script: "exit 0", expected: "PHPMON_FILE_HANDLE_READ_FAILURE"),
        OutputCase(script: "printf '\\377'", expected: "PHPMON_FILE_HANDLE_READ_FAILURE")
    ])
    func execute_preserves_output_behavior(_ sample: OutputCase) async {
        let output = await runBlocking {
            RealCommand().execute(
                path: "/bin/sh", arguments: ["-c", sample.script],
                trimNewlines: sample.trimNewlines, withStandardError: sample.withStandardError
            )
        }

        #expect(output == sample.expected)
    }

    nonisolated struct OutputCase: Sendable {
        let script: String
        let expected: String
        var trimNewlines = false
        var withStandardError = false
    }

    @Test func execute_distinguishes_signal_termination_from_launch_failure() async {
        let output = await runBlocking {
            RealCommand().execute(path: "/bin/sh", arguments: ["-c", "kill -TERM $$"])
        }

        #expect(output == "PHPMON_COMMAND_UNCAUGHT_SIGNAL")
    }

    @Test func execute_returns_failure_when_executable_is_missing() async {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("php-config").path

        let output = await runBlocking {
            RealCommand().execute(path: path, arguments: ["--version"], trimNewlines: true)
        }

        #expect(output == "PHPMON_COMMAND_LAUNCH_FAILURE")
    }

    @Test(arguments: [false, true])
    func execute_returns_failure_when_detected_executable_becomes_inaccessible(_ removed: Bool) async throws {
        let executable = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("#!/bin/sh\necho 8.4.2\n".utf8).write(to: executable)
        defer { try? FileManager.default.removeItem(at: executable) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))

        if removed {
            try FileManager.default.removeItem(at: executable)
        } else {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: executable.path)
        }

        let output = await runBlocking {
            RealCommand().execute(
                path: executable.path, arguments: [], trimNewlines: false, withStandardError: true
            )
        }

        #expect(output == "PHPMON_COMMAND_LAUNCH_FAILURE")
    }

    @Test func fake_command_outputs_can_change_while_probes_run() async {
        let command = TestableCommand(commands: ["php --version": "8.4.2"])

        await runBlocking {
            DispatchQueue.concurrentPerform(iterations: 32) { index in
                command.updateOutputs(["probe \(index)": "\(index)"])
                #expect(command.execute(
                    path: "probe", arguments: ["\(index)"], trimNewlines: false, withStandardError: false
                ) == "\(index)")
                #expect(command.execute(
                    path: "php", arguments: ["--version"], trimNewlines: false, withStandardError: false
                ) == "8.4.2")
            }
        }

        #expect(command.commands.count == 33)
    }

    @Test func execute_drains_output_before_waiting_for_exit() {
        let output = RealCommand().execute(
            path: "/usr/bin/perl",
            arguments: ["-e", "alarm 2; print STDOUT 'x' x 131072; print STDERR 'y' x 131072; alarm 0;"],
            trimNewlines: false,
            withStandardError: true
        )

        #expect(output.utf8.count == 262144)
    }

    @Test(.enabled(if: Binaries.hasLinkedPhp(), "Requires PHP"))
    func determinePhpVersion() {
        let container = Container.real(minimal: true)

        let version = container.command.execute(
            path: container.paths.php,
            arguments: ["-v"],
            trimNewlines: false
        )

        #expect(version.contains("(cli)"))
        #expect(version.contains("NTS"))
        #expect(version.contains("built"))
        #expect(version.contains("Zend"))
    }
}
