//
//  BrewPhpFormulaSourceTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Foundation
import Testing

struct BrewPhpFormulaSourceTest {
    @Test func snapshot_commit_comes_from_the_source_url_not_a_resource_or_bottle() {
        let commit = String(repeating: "a", count: 40)
        let source = BrewPhpFormulaSource.from("""
        class PhpAT87 < Formula
          url "https://github.com/php/php-src/archive/\(commit).tar.gz?commit=\(commit)"
          version "8.7.0"
          bottle do
            sha256 arm64_tahoe: "not-the-source-commit"
          end
          resource "example" do
            url "https://example.com/resource.tar.gz"
          end
        end
        """)
        #expect(source == .snapshot(commit: commit))
        #expect(source.isPrerelease == true)
    }

    @Test(arguments: ["8.6.0alpha1", "8.6.0beta2", "8.6.0RC5", "8.6.0"])
    func release_archives_preserve_prerelease_labels(_ version: String) {
        let source = BrewPhpFormulaSource.from(
            url: "https://downloads.php.net/~release-manager/php-\(version).tar.xz", version: nil
        )
        #expect(source == .release(version: version))
        #expect(source.isPrerelease == (version != "8.6.0"))
    }

    @Test func backports_are_stable_and_unrecognized_metadata_stays_unknown() {
        let source = BrewPhpFormulaSource.from(
            url: "https://github.com/shivammathur/php-src-backports/archive/abcdef.tar.gz", version: "7.4.33"
        )
        #expect(source == .release(version: "7.4.33"))
        #expect(source.isPrerelease == false)
        for url in [
            "https://github.com/php/php-src/archive/master.tar.gz",
            "https://example.com/php-8.7.0.tar.gz",
            "https://github.com.evil.test/php/php-src/archive/\(String(repeating: "a", count: 40)).tar.gz"
        ] {
            #expect(BrewPhpFormulaSource.from(url: url, version: "8.7.0") == .unknown)
        }
        #expect(BrewPhpFormulaSource.from("unreadable formula").isPrerelease == nil)
    }

    @Test func nightly_changes_do_not_require_a_new_php_version() {
        #expect(BrewPhpUpdateCheck.compare(
            installed: .snapshot(commit: "old"), available: .snapshot(commit: "new"), homebrewUpgrade: nil
        ) == .available(.reinstallSnapshot(installedCommit: "old", availableCommit: "new")))
        #expect(BrewPhpUpdateCheck.compare(
            installed: .snapshot(commit: "same"), available: .snapshot(commit: "same"), homebrewUpgrade: nil
        ) == .current)
        #expect(BrewPhpUpdateCheck.compare(
            installed: .unknown, available: .snapshot(commit: "new"), homebrewUpgrade: nil
        ) == .unknown)
    }

    @Test(arguments: ["8.6.0alpha1", "8.6.0beta2", "8.6.0RC5"])
    func prerelease_to_stable_uses_homebrew_upgrade_or_reinstall_as_needed(_ version: String) {
        #expect(BrewPhpUpdateCheck.compare(
            installed: .release(version: version), available: .release(version: "8.6.0"), homebrewUpgrade: "8.6.0"
        ) == .available(.upgrade(version: "8.6.0")))
        #expect(BrewPhpUpdateCheck.compare(
            installed: .release(version: version), available: .release(version: "8.6.0"), homebrewUpgrade: nil
        ) == .available(.reinstallRelease(version: "8.6.0")))
    }

    @Test func nightly_to_stable_replaces_the_snapshot_even_when_homebrew_considers_it_current() {
        #expect(BrewPhpUpdateCheck.compare(
            installed: .snapshot(commit: "old"), available: .release(version: "8.6.0"), homebrewUpgrade: nil
        ) == .available(.reinstallRelease(version: "8.6.0")))
    }

    @Test func normal_upgrades_take_precedence_over_commit_changes() {
        #expect(BrewPhpUpdateCheck.compare(
            installed: .snapshot(commit: "old"), available: .snapshot(commit: "new"), homebrewUpgrade: "8.7.0_2"
        ) == .available(.upgrade(version: "8.7.0_2")))
    }
}
