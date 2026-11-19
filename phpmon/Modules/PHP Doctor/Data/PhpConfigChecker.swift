//
//  PhpConfigChecker.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 24/02/2023.
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Foundation

class PhpConfigChecker {
    public static var shared = PhpConfigChecker(App.shared.container)

    /// Missing files that only reinstalling or switching PHP can restore.
    var missing: [String] = []

    /// PHP versions without a Valet pool file, which PHP Monitor can create from Valet's own template.
    var missingValetPools: [String] = []

    var container: Container

    init(_ container: Container) {
        self.container = container
    }

    public func check() {
        missing = []
        missingValetPools = []
        // Valet 3 and newer use a pool file that PHP Monitor can recreate, see `InternalSwitcher`.
        let restoresValetPools = container.valet.installed && (container.valet.version?.major ?? 0) > 2

        let shouldExist: [FileExistenceCheck] = [
            FileExistenceCheck(condition: nil, path: "php.ini"),
            FileExistenceCheck(condition: nil, path: "php-fpm.conf"),
            FileExistenceCheck(condition: { self.container.valet.installed }, path: Self.valetPool)
        ]

        for version in container.phpEnvs.availablePhpVersions {
            for file in shouldExist {
                // Early exit in case our condition is not met
                if file.condition != nil && file.condition!() == false {
                    continue
                }

                // Do the check
                let fullFilePath = container.paths.etcPath.appending("/php/\(version)/\(file.path)")
                if !container.filesystem.fileExists(fullFilePath) {
                    if file.path == Self.valetPool && restoresValetPools {
                        missingValetPools.append(version)
                    } else {
                        missing.append(fullFilePath)
                    }
                }
            }
        }

        if !missing.isEmpty {
            Log.warn("The following config file(s) were missing: \(missing)")
        }
        if !missingValetPools.isEmpty {
            Log.warn("These PHP versions have no Valet pool file: \(missingValetPools)")
        }
    }

    static let valetPool = "php-fpm.d/valet-fpm.conf"

    /// The full path of a version's Valet pool file.
    func valetPoolPath(for version: String) -> String {
        return container.paths.etcPath.appending("/php/\(version)/\(Self.valetPool)")
    }
}

struct FileExistenceCheck {
    let condition: (() -> Bool)?
    let path: String
}
