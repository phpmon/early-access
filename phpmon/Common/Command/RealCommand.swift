//
//  Command.swift
//  PHP Monitor
//
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Cocoa

// Nonisolated + Sendable: stateless, runs subprocesses to completion, must stay off the
// main actor once the app moves to main-actor-by-default.
public nonisolated final class RealCommand: CommandProtocol, Sendable {
    init() {}

    public func execute(
        path: String,
        arguments: [String],
        trimNewlines: Bool,
        withStandardError: Bool
    ) -> String {
        warnIfBlockingOnMainThread("command.execute: \(path)")

        let task = Process()
        var output = ""

        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }

        if withStandardError {
            task.standardError = pipe
        }

        // A binary can disappear after detection, for example during a Homebrew upgrade.
        // launch() raises an Objective-C exception that Swift cannot catch.
        do {
            try task.run()
        } catch {
            Log.err("Could not launch command `\(path) w/ args: \(arguments)`: \(error)")
            return "PHPMON_COMMAND_LAUNCH_FAILURE"
        }
        let data = try? pipe.fileHandleForReading.readToEnd()
        task.waitUntilExit()

        // Handle termination
        if task.terminationReason == .uncaughtSignal {
            Log.err("The command `\(path) w/ args: \(arguments)` likely crashed. Returning UNCAUGHT_SIGNAL.")
            return "PHPMON_COMMAND_UNCAUGHT_SIGNAL"
        }

        // Decode the captured output.
        if let data,
            let string = String(data: data, encoding: .utf8) {
            output = string
        } else {
            return "PHPMON_FILE_HANDLE_READ_FAILURE"
        }

        // Trim newline output if necessary
        if trimNewlines {
            return output.components(separatedBy: .newlines)
                .filter({ !$0.isEmpty })
                .joined(separator: "\n")
        }

        return output
    }

    public func execute(
        path: String,
        arguments: [String],
        trimNewlines: Bool = false
    ) -> String {
        self.execute(
            path: path,
            arguments: arguments,
            trimNewlines: trimNewlines,
            withStandardError: false
        )
    }
}
