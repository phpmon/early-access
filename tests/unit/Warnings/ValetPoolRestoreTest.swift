//
//  ValetPoolRestoreTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Testing

@MainActor
struct ValetPoolRestoreTest {
    private let root = "/Users/fake/.composer/vendor/laravel/valet"
    private let etc = "/opt/homebrew/etc/php"
    private let warningName = "Valet pool files are missing for some PHP versions"

    @Test(arguments: [2, 4])
    func only_valet_3_and_newer_pools_are_offered_as_an_automatic_fix(_ valetMajor: Int) {
        let manager = makeWarningManager(valetMajor: valetMajor)
        manager.phpConfigChecker.check()

        // PHP 8.6 lacks its pool. Valet 2 keeps the manual advice, since PHP Monitor cannot create its pool.
        #expect(manager.phpConfigChecker.missingValetPools == (valetMajor > 2 ? ["8.6"] : []))
        #expect(manager.phpConfigChecker.missing == (valetMajor > 2 ? [] : ["\(etc)/8.6/php-fpm.d/valet-fpm.conf"]))
    }

    @Test func the_fix_creates_missing_pools_from_valets_template() async throws {
        let manager = makeWarningManager(valetMajor: 4)
        let warning = try #require(manager.allAvailableWarnings().first { $0.name == warningName })
        #expect(await warning.applies())

        let fix = try #require(warning.fix)
        await fix()

        let filesystem = manager.container.filesystem!
        #expect(try filesystem.getStringFromFile("\(etc)/8.6/php-fpm.d/valet-fpm.conf") == "listen = valet86.sock")
        #expect(try filesystem.getStringFromFile("\(etc)/8.5/php-fpm.d/valet-fpm.conf") == "existing")
        #expect(!manager.warnings.contains { $0.name == warningName })
    }

    @Test func php_version_manager_creates_pools_only_for_the_versions_it_changed() async throws {
        let manager = makeWarningManager(valetMajor: 4, poolFor85: false)
        let container = manager.container
        let install = BrewPhpFormula(container, name: "php@8.6", displayName: "PHP 8.6", installedVersion: nil)
        let command = ModifyPhpVersionCommand(container, title: "Test", upgrading: [], installing: [install])

        await command.restoreValetConfiguration()

        #expect(container.filesystem.fileExists("\(etc)/8.6/php-fpm.d/valet-fpm.conf"))
        #expect(!container.filesystem.fileExists("\(etc)/8.5/php-fpm.d/valet-fpm.conf"))
    }

    private func makeWarningManager(valetMajor: Int, poolFor85: Bool = true) -> WarningManager {
        var files: [String: FakeFile] = [
            "/opt/homebrew/bin/brew": .fake(.binary),
            "/opt/homebrew/bin/valet": .fake(.symlink, "\(root)/valet"),
            "\(root)/valet": .fake(.binary),
            "\(root)/cli/stubs/etc-phpfpm-valet.conf": .fake(.text, "listen = valet.sock")
        ]
        for version in ["8.5", "8.6"] {
            files["\(etc)/\(version)/php.ini"] = .fake(.text, "")
            files["\(etc)/\(version)/php-fpm.conf"] = .fake(.text, "")
        }
        if poolFor85 {
            files["\(etc)/8.5/php-fpm.d/valet-fpm.conf"] = .fake(.text, "existing")
        }

        let container = Container()
        container.withFakeSystemContext(architecture: "arm64", configuredShell: "/bin/zsh")
        container.bind(coreOnly: false, commandTracking: false)
        container.overrideFake(
            shellExpectations: [
                "sysctl -n sysctl.proc_translated": .instant("0"),
                "/opt/homebrew/bin/brew tap": .instant("shivammathur/php\nshivammathur/extensions"),
                "/opt/homebrew/bin/brew help trust": .instant("Usage: brew trust [options] [target ...]\n"),
                "/opt/homebrew/bin/brew trust --tap": .instant("Trusted taps:\n  shivammathur/php\n  shivammathur/extensions")
            ],
            fileSystemFiles: files,
            commandTracking: false
        )
        container.valet.installed = true
        container.valet.version = VersionNumber(major: valetMajor, minor: 0, patch: 0)
        container.phpEnvs.availablePhpVersions = ["8.6", "8.5"]
        return WarningManager(container: container)
    }
}
