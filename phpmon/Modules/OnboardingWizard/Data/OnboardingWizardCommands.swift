extension ShellEnvironment {
    func pathInstructionLines() -> [String] {
        // The `export` lines do not work in fish: inside a word, fish expands the list `$PATH`
        // once per entry, so the line sets a mangled PATH. `fish_add_path` is not an option either,
        // because it skips directories that do not exist yet. On a fresh setup, that includes
        // Composer's bin directory, which the PATH step requires before Composer is installed.
        if configuredShellIsFish {
            return [
                "set -gx PATH ~/.config/phpmon/bin $PATH",
                "set -gx PATH ~/.composer/vendor/bin $PATH",
                "set -gx PATH \(container.paths.binPath) $PATH"
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
