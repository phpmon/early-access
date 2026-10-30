//
//  FishShellPathTest.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 30/10/2026.
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Testing
import Foundation

@Suite
struct FishShellPathTest {
    private let markerPath = "/phpmon/fake/fish/bin"

    /**
     Creates a stand-in for fish, so the test does not depend on fish being installed.

     fish stores PATH as a list. An unquoted `$PATH` expands to one word per entry, which `echo`
     prints separated by spaces. A quoted `"$PATH"` joins the entries with colons. `sh` behaves
     the same way when `IFS` is a colon, so the script runs the command it receives that way.

     The script also adds `markerPath` to PATH. The fallback PATH that `getPath` uses when the
     shell fails or times out never contains it, so the test cannot pass by way of the fallback.
     */
    private func createFakeFish(in directory: String) -> String {
        let path = "\(directory)/fish"

        FileManager.default.createFile(
            atPath: path,
            contents: Data("""
                #!/bin/sh
                # The command to run is the last argument, after the login and interactive flags.
                shift $(($# - 1))
                PATH="\(markerPath):$PATH"
                IFS=:
                eval "$1"
                """.utf8),
            attributes: [.posixPermissions: 0o755]
        )

        return path
    }

    @Test func fish_shell_path_is_colon_separated() throws {
        let directory = "\(NSTemporaryDirectory())phpmon-fish-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }

        // `ShellEnvironment` splits on colons, so a space-separated PATH matches no entries.
        // The generous timeout keeps a busy machine from falling back to the system PATH.
        let path = RealShell.getPath(shell: createFakeFish(in: directory), timeout: 30)
        let entries = path.split(separator: ":").map(String.init)

        #expect(entries.contains(markerPath))
    }
}
