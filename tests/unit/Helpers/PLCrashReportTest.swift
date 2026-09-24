//
//  PLCrashReportTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Testing
import CrashReporter

struct PLCrashReportTest {
    // A child crash can produce a report containing only healthy parent threads.
    @Test(arguments: [[], [false], [false, false, false]])
    func report_without_a_crashed_app_thread_is_rejected(_ crashed: [Bool]) {
        let report = ReportWithThreads(crashed: crashed)
        #expect(!report.hasCrashedThread)
    }

    @Test(arguments: [[true], [true, false], [false, true, false], [false, false, true]])
    func crashed_app_thread_is_found_anywhere_in_the_report(_ crashed: [Bool]) {
        let report = ReportWithThreads(crashed: crashed)
        #expect(report.hasCrashedThread)
    }
}

private nonisolated final class ReportWithThreads: PLCrashReport {
    private let reportThreads: [PLCrashReportThreadInfo]

    init(crashed: [Bool]) {
        reportThreads = crashed.enumerated().map { index, crashed in
            PLCrashReportThreadInfo(threadNumber: index, stackFrames: [], crashed: crashed, registers: [])
        }
        super.init()
    }

    override var threads: [Any]! { reportThreads }
}
