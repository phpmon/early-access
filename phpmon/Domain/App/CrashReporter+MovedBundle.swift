//
//  CrashReporter+MovedBundle.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Foundation
import CrashReporter

/**
 `Bundle.main` keeps the path the app was launched from. If the app is moved or deleted while it
 is running, any resource that was not loaded yet can no longer be found. NVAlert's resource bundle
 is one of them, and its generated accessor calls `fatalError` when it is missing. A crash like that
 is not a bug in the app, so it is not reported.

 The check runs when the app crashes: PLCrashReporter calls `markCrashAfterBundleMove` after it has
 written the report. If the bundle is gone, the callback leaves a marker file, and the next launch
 discards the report instead of asking the user to send it.
 */
extension CrashReporter {

    /**
     The paths the crash callback needs. They are prepared at launch, because the callback runs while
     the process is crashing and may only use async-signal-safe calls: no allocation, no Foundation.
     */
    nonisolated struct MovedBundleCheck {
        let infoPlistPath: UnsafeMutablePointer<CChar>
        let markerPath: UnsafeMutablePointer<CChar>
    }

    /** The marker file that the crash callback creates when the bundle was gone at crash time. */
    static var movedBundleMarker: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.nicoverbruggen.phpmon")
            .appendingPathComponent("crashed-after-bundle-move")
    }

    /**
     Prepares the callback context. It is never freed: PLCrashReporter keeps the pointer for the
     lifetime of the process.
     */
    static func movedBundleCheck(bundle: URL, marker: URL) -> UnsafeMutablePointer<MovedBundleCheck> {
        try? FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        let check = UnsafeMutablePointer<MovedBundleCheck>.allocate(capacity: 1)
        check.initialize(to: MovedBundleCheck(
            infoPlistPath: strdup(bundle.appendingPathComponent("Contents/Info.plist").path),
            markerPath: strdup(marker.path)
        ))
        return check
    }

    /** Runs inside the crashing process, after the crash report has been written. */
    nonisolated static let markCrashAfterBundleMove: PLCrashReporterPostCrashSignalCallback = { _, _, context in
        guard let check = context?.assumingMemoryBound(to: MovedBundleCheck.self).pointee,
              access(check.infoPlistPath, F_OK) != 0
        else {
            return
        }

        // `creat` instead of `open`: Swift reaches the variadic `open` through an overlay wrapper.
        let marker = creat(check.markerPath, 0o644)
        if marker >= 0 {
            close(marker)
        }
    }

    /**
     Returns whether the previous session crashed after its bundle was moved, and removes the marker
     so it never applies to a later crash.
     */
    static func takeMovedBundleMarker(_ marker: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: marker.path) else {
            return false
        }

        try? FileManager.default.removeItem(at: marker)
        return true
    }
}
