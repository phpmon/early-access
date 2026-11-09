//
//  FakeBrewFormulaeHandler.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 27/05/2023.
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Foundation

class FakeBrewFormulaeHandler: HandlesBrewPhpFormulae {
    let container: Container
    let formulae: BrewFormulaeObservable

    init(_ container: Container = App.shared.container, formulae: BrewFormulaeObservable = BrewFormulaeObservable()) {
        self.container = container
        self.formulae = formulae
    }

    public func loadPhpVersions(loadOutdated: Bool) async -> [BrewPhpFormula] {
        return [
            BrewPhpFormula(
                container,
                name: "php@9.9",
                displayName: "PHP 9.9",
                installedVersion: nil,
                updateCheck: .available(.upgrade(version: "9.9.0")),
                prerelease: true
            ),
            BrewPhpFormula(
                container,
                name: "php@8.4",
                displayName: "PHP 8.4",
                installedVersion: nil,
                updateCheck: .available(.upgrade(version: "8.4.0")),
                prerelease: true
            ),
            BrewPhpFormula(
                container,
                name: "php",
                displayName: "PHP 8.3",
                installedVersion: nil,
                updateCheck: .available(.upgrade(version: "8.3.0")),
                prerelease: true
            ),
            BrewPhpFormula(
                container,
                name: "php@8.2",
                displayName: "PHP 8.2",
                installedVersion: "8.2.3",
                updateCheck: .available(.upgrade(version: "8.2.4"))
            ),
            BrewPhpFormula(
                container,
                name: "php@8.1",
                displayName: "PHP 8.1",
                installedVersion: "8.1.17",
                updateCheck: .unknown
            ),
            BrewPhpFormula(
                container,
                name: "php@8.0",
                displayName: "PHP 8.0",
                installedVersion: nil,
                updateCheck: .unknown
            ),
            BrewPhpFormula(
                container,
                name: "php@7.4",
                displayName: "PHP 7.4",
                installedVersion: nil,
                updateCheck: .unknown
            ),
            BrewPhpFormula(
                container,
                name: "php@7.3",
                displayName: "PHP 7.3",
                installedVersion: nil,
                updateCheck: .unknown
            ),
            BrewPhpFormula(
                container,
                name: "php@7.2",
                displayName: "PHP 7.2",
                installedVersion: nil,
                updateCheck: .unknown
            ),
            BrewPhpFormula(
                container,
                name: "php@7.1",
                displayName: "PHP 7.1",
                installedVersion: nil,
                updateCheck: .unknown
            )
        ]
    }
}
