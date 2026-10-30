//
//  OnboardingWizardShellEnvironmentTest.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 27/04/2026.
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Testing

struct OnboardingWizardShellEnvironmentTest {
    // The Homebrew PATH line should use the Apple Silicon prefix on arm64 systems.
    @Test func homebrew_path_line_uses_detected_arm64_prefix() {
        let container = makeOnboardingContainer(architecture: "arm64")

        #expect(
            ShellEnvironment(container).homebrewBinPathExport
                == "export PATH=$HOME/bin:/opt/homebrew/bin:$PATH"
        )
    }

    // The Homebrew PATH line should use the Intel prefix on x86_64 systems.
    @Test func homebrew_path_line_uses_detected_intel_prefix() {
        let container = makeOnboardingContainer(architecture: "x86_64")

        #expect(
            ShellEnvironment(container).homebrewBinPathExport
                == "export PATH=$HOME/bin:/usr/local/bin:$PATH"
        )
    }

    // Composer's global vendor bin path should always be inserted before Homebrew.
    @Test func composer_path_line_matches_documented_vendor_bin_location() {
        #expect(
            ShellEnvironment(makeOnboardingContainer(architecture: "arm64")).composerBinPathExport
                == "export PATH=$HOME/bin:~/.composer/vendor/bin:$PATH"
        )
    }

    // The onboarding PATH guidance should include PHP Monitor helpers before the other required bins.
    @Test func onboarding_path_instructions_include_php_monitor_helpers() {
        let lines = ShellEnvironment(makeOnboardingContainer(architecture: "arm64")).pathInstructionLines()

        #expect(
            lines == [
                "export PATH=$HOME/bin:~/.config/phpmon/bin:$PATH",
                "export PATH=$HOME/bin:~/.composer/vendor/bin:$PATH",
                "export PATH=$HOME/bin:/opt/homebrew/bin:$PATH"
            ]
        )
    }

    // fish users get `set -gx PATH` lines, since the `export` lines mangle the PATH in fish.
    // fish does not need to be installed: the configured shell decides which lines are shown.
    @Test func onboarding_path_instructions_use_fish_syntax_for_fish_users() {
        let shellEnvironment = ShellEnvironment(makeOnboardingContainer(
            architecture: "arm64",
            configuredShell: "/opt/homebrew/bin/fish"
        ))

        #expect(
            shellEnvironment.pathInstructionLines() == [
                "set -gx PATH ~/.config/phpmon/bin $PATH",
                "set -gx PATH ~/.composer/vendor/bin $PATH",
                "set -gx PATH /opt/homebrew/bin $PATH"
            ]
        )
        #expect(
            shellEnvironment.pathInstructionTitle()
                == "onboarding_wizard.command.path.title.fish".localized
        )
    }

    // On a fresh setup, none of the directories exist yet. Composer's bin directory is only
    // created by the PHP & Composer step, which comes after the PATH step. So the fish lines must
    // add each directory to the PATH even when it does not exist, or the PATH step never passes.
    @Test func fish_path_instructions_configure_path_before_directories_exist() throws {
        let container = makeOnboardingFakeContainer(
            architecture: "arm64",
            configuredShell: "/opt/homebrew/bin/fish",
            shell: [:],
            files: [:]
        )
        let shell = try #require(container.shell as? TestableShell)
        let shellEnvironment = ShellEnvironment(container)
        shell.PATH = "/usr/bin:/bin"

        for line in shellEnvironment.pathInstructionLines() {
            shell.PATH = applyFishPathLine(line, to: shell.PATH, in: container)
        }

        let unconfiguredPaths = shellEnvironment.onboardingPathStatus()
            .filter { !$0.configured }
            .map(\.path)

        #expect(unconfiguredPaths.isEmpty)
        #expect(shellEnvironment.hasRequiredOnboardingPaths())
    }

    /**
     Applies one fish line to a colon-separated PATH the way fish does, so the test can check the
     resulting PATH without fish being installed. Directories exist only in the fake filesystem.

     - `set -gx PATH <directories> $PATH` prepends the directories, whether they exist or not.
     - `fish_add_path <directory>` prepends the directory only if it exists and is not in the PATH.

     Any other line is recorded as an issue, so the test cannot pass on a line it does not model.
     */
    private func applyFishPathLine(_ line: String, to path: String, in container: Container) -> String {
        let words = line.split(separator: " ").map { word in
            word.hasPrefix("~/")
                ? container.paths.homePath + word.dropFirst()
                : String(word)
        }
        let entries = path.split(separator: ":").map(String.init)

        if words.count > 4, words.prefix(3) == ["set", "-gx", "PATH"], words.last == "$PATH" {
            return (words.dropFirst(3).dropLast() + entries).joined(separator: ":")
        }

        if words.count == 2, words[0] == "fish_add_path" {
            let directory = words[1]
            guard container.filesystem.directoryExists(directory), !entries.contains(directory) else {
                return path
            }
            return ([directory] + entries).joined(separator: ":")
        }

        Issue.record("The test does not model this fish line: \(line)")
        return path
    }
}
