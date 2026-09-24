//
//  PLCrashReportExtension.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import CrashReporter

extension PLCrashReport {
    /// Child processes can inherit the Mach exception port. PLCrashReporter then
    /// records the parent's threads, none of which is the child's crashed thread.
    var hasCrashedThread: Bool {
        threads.contains { ($0 as? PLCrashReportThreadInfo)?.crashed == true }
    }
}
