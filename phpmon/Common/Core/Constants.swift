//
//  Constants.swift
//  PHP Monitor
//
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Cocoa

nonisolated struct Constants {

    /**
     The minimum version of Valet that is recommended.
     If the installed version is older, a notification will be shown
     every time the app launches (with a recommendation to upgrade).

     See also: https://github.com/laravel/valet/releases/tag/v2.16.2
     */
    static let MinimumRecommendedValetVersion = "2.16.2"

    /**
     The amount of seconds that is considered the threshold for
     PHP Monitor to mark any given launch as a "slow" launch.

     If the startup procedure was slow (or hangs), this message should
     be displayed. This is based on an appropriate launch time on a
     basic M1 Apple chip, with some margin for slower Intel chips.
     */
    static let SlowBootThresholdInterval: TimeInterval = .seconds(30)

    /**
     The interval between automatic background update checks.
     */
    static let AutomaticUpdateCheckInterval: TimeInterval = .hours(24)

    /**
     The minimum interval that must pass before allowing another
     automatic update check. This prevents excessive checking
     on frequent app restarts (due to crashes or bad config).
     */
    static let MinimumUpdateCheckInterval: TimeInterval = .minutes(60)

    /**
     Retry intervals for failed automatic update checks.
     Uses exponential backoff before falling back to normal schedule.
     */
    static let UpdateCheckRetryIntervals: [TimeInterval] = [
        .minutes(5),
        .minutes(15),
        .hours(1),
        .hours(3)
    ]

    /**
     The app uses these external taps to ensure that various
     PHP versions and extensions can be installed.
     */
    struct Taps {
        static let php: String = "shivammathur/php"
        static let extensions: String = "shivammathur/extensions"
    }

    /**
     Warn when the bundled list of PHP series may be out of date after the next annual PHP release.
     */
    static let PhpFormulaeCutoffDate = "2027-11-30" // YYYY-MM-DD

    /**
     The major versions of Homebrew that are supported.
     */
    static let SupportedHomebrewVersions: Set = [4, 5, 6, 7]

    /**
     * The PHP versions supported by this application.
     * Any other PHP versions are considered invalid.
     */
    static let DetectedPhpVersions: Set = [
        "5.6",
        "7.0", "7.1", "7.2", "7.3", "7.4",
        "8.0", "8.1", "8.2", "8.3", "8.4",
        "8.5",
        "8.6", "8.7"
    ]

    /**
     Known PHP support by Valet major when the installed list cannot be read.
     */
    static let ValetPhpVersionsWithoutEdits: [Int: Set] = [
        2: // Valet v2 has the broadest legacy support
        [
            "5.6",
            "7.0", "7.1", "7.2", "7.3", "7.4",
            "8.0", "8.1", "8.2"
        ],
        3: // Valet v3 dropped support for v5.6
        [
            "7.0", "7.1", "7.2", "7.3", "7.4",
            "8.0", "8.1", "8.2", "8.3", "8.4"
        ],
        4: // Valet v4 dropped support for v7.0
        [
            "7.1", "7.2", "7.3", "7.4",
            "8.0", "8.1", "8.2", "8.3", "8.4",
            "8.5"
        ]
    ]

    /// The switcher also handles newer PHP series with temporary Valet support.
    static let ValetSupportedPhpVersionMatrix = ValetPhpVersionsWithoutEdits.merging([4: ["8.6", "8.7"]]) {
        $0.union($1)
    }

    struct Urls {
        // Useful Links
        static let DonationPage = url("https://phpmon.app/sponsor")
        static let FrequentlyAskedQuestions = url("https://phpmon.app/faq")
        static let DonationPayment = url("https://phpmon.app/sponsor/now")

        // Wiki
        static let WikiPhpUnavailable = url("https://phpmon.app/php-unavailable")
        static let WikiPhpUpgrade = url("https://phpmon.app/php-upgrade")

        // Dependencies
        static let AppleCommandLineTools = url("https://phpmon.app/install-apple-devtools")
        static let HomebrewWebsite = url("https://phpmon.app/install-homebrew")

        // API endpoints
        #if DEBUG
        static let UpdateCheckEndpoint = url("https://api.phpmon.test/api/v1/update-check")
        static let CrashReportingEndpoint = url("https://api.phpmon.test/api/v1/report-crash")
        #else
        static let UpdateCheckEndpoint = url("https://api.phpmon.app/api/v1/update-check")
        static let CrashReportingEndpoint = url("https://api.phpmon.app/api/v1/report-crash")
        #endif

        // Early Access Changelog
        static let EarlyAccessChangelog = url("https://phpmon.app/early-access/release-notes")

        // GitHub Releases (do not alias these)
        static let GitHubReleases = url("https://github.com/nicoverbruggen/phpmon/releases")
    }
}
