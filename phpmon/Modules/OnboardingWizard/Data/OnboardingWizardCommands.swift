extension ShellEnvironment {
    func pathInstructionLines() -> [String] {
        // The `export` lines do not work in fish: inside a word, fish expands the list `$PATH`
        // once per entry, so the line sets a mangled PATH. `fish_add_path` adds each directory once.
        if configuredShellIsFish {
            return [
                "fish_add_path ~/.config/phpmon/bin",
                "fish_add_path ~/.composer/vendor/bin",
                "fish_add_path \(container.paths.binPath)"
            ]
        }

        return [
            phpMonitorBinPathExport,
            composerBinPathExport,
            homebrewBinPathExport
        ]
    }

    func pathInstructionTitle() -> String {
        if configuredShellIsFish {
            return "onboarding_wizard.command.path.title.fish".localized
        }

        return "onboarding_wizard.command.path.title".localized
    }

    /**
     Uses the configured shell, since that is the shell the user types the instructions into.
     (The resolved shell falls back to zsh when the configured shell is not accessible.)
     */
    private var configuredShellIsFish: Bool {
        return configuredShell.contains("/fish")
    }
}
