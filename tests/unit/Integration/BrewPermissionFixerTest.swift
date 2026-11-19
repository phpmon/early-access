//
//  BrewPermissionFixerTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Testing

@MainActor
struct BrewPermissionFixerTest {
    private let opt = "/opt/homebrew/opt"
    private let valetStop = "sudo /opt/homebrew/bin/valet stop php"

    @Test func versions_without_root_owned_folders_need_no_stop_or_password() async throws {
        let runner = OnboardingTestPrivilegedCommandRunner()
        let container = makeContainer(rootOwned: ["8.6"], runner: runner)

        #expect(try await BrewPermissionFixer(container).restoreOwnership(of: ["8.7"]) == false)
        #expect(!ran(valetStop, in: container))
        #expect(runner.requests.isEmpty)
    }

    @Test func valet_restores_ownership_without_a_password() async throws {
        let runner = OnboardingTestPrivilegedCommandRunner()
        let container = makeContainer(rootOwned: ["8.7"], valetGivesBack: true, runner: runner)

        #expect(try await BrewPermissionFixer(container).restoreOwnership(of: ["8.7"]))
        #expect(ran(valetStop, in: container))
        #expect(runner.requests.isEmpty)
    }

    @Test(arguments: [nil, 2, 4])
    func remaining_root_owned_folders_of_the_requested_versions_ask_for_a_password(_ valetMajor: Int?) async throws {
        let runner = OnboardingTestPrivilegedCommandRunner()
        let container = makeContainer(rootOwned: ["8.6", "8.7"], valetMajor: valetMajor, runner: runner)

        #expect(try await BrewPermissionFixer(container).restoreOwnership(of: ["8.7"]))
        // Without Valet there is nothing to ask, and Valet 2 never gives ownership back.
        #expect(ran(valetStop, in: container) == ((valetMajor ?? 0) >= 3))
        #expect(runner.requests.count == 1)
        let script = try #require(runner.requests.first?.0)
        #expect(script.contains("chown -R \(container.paths.whoami):admin \(opt)/php@8.7/bin"))
        #expect(script.contains("chown -R \(container.paths.whoami):admin \(opt)/php@8.7/sbin"))
        #expect(!script.contains("php@8.6"))
        #expect(runner.requests.first?.1 == .restoreHomebrewOwnership)
    }

    @Test func a_cancelled_password_dialog_is_reported() async throws {
        let runner = OnboardingTestPrivilegedCommandRunner(responses: [.deny])
        let container = makeContainer(rootOwned: ["8.7"], runner: runner)

        await #expect(throws: AdminPrivilegeError(kind: .userDenied)) {
            try await BrewPermissionFixer(container).restoreOwnership(of: ["8.7"])
        }
    }

    private func makeContainer(
        rootOwned: Set<String>,
        valetMajor: Int? = 4,
        valetGivesBack: Bool = false,
        runner: PrivilegedCommandRunner
    ) -> Container {
        var files: [String: FakeFile] = [:]
        for version in ["8.6", "8.7"] {
            for folder in ["bin", "sbin"] {
                files["\(opt)/php@\(version)/\(folder)"] = .fake(.directory, ownedByRoot: rootOwned.contains(version))
            }
        }
        // Valet's `stop php` gives the folders of the PHP versions it stops back to the user.
        let givenBack: [FakeShellTransaction] = valetGivesBack
            ? rootOwned.flatMap { version in ["bin", "sbin"].map { .write("", to: "\(opt)/php@\(version)/\($0)") } }
            : []
        let container = Container.fake(
            shell: [valetStop: BatchFakeShellOutput(items: [.instant("Stopping PHP...")], transactions: givenBack)],
            files: files,
            privilegedCommandRunner: runner
        )
        container.valet.installed = valetMajor != nil
        container.valet.version = valetMajor.map { VersionNumber(major: $0, minor: 0, patch: 0) }
        return container
    }

    private func ran(_ command: String, in container: Container) -> Bool {
        container.commandTracker.commands.contains { $0.command == command }
    }
}
