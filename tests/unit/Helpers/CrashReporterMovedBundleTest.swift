//
//  CrashReporterMovedBundleTest.swift
//  PHP Monitor
//
//  Copyright © 2026 Nico Verbruggen. All rights reserved.
//

import Testing
import Foundation

struct CrashReporterMovedBundleTest {

    @Test func crash_after_the_bundle_was_moved_leaves_a_marker() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try Self.makeBundle(at: root.appendingPathComponent("Applications/PHP Monitor.app"))
        let marker = root.appendingPathComponent("Caches/crashed-after-bundle-move")
        let check = CrashReporter.movedBundleCheck(bundle: bundle, marker: marker)

        try FileManager.default.moveItem(at: bundle, to: root.appendingPathComponent("PHP Monitor.app"))
        CrashReporter.markCrashAfterBundleMove(nil, nil, UnsafeMutableRawPointer(check))

        #expect(FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func crash_with_the_bundle_in_place_leaves_no_marker() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try Self.makeBundle(at: root.appendingPathComponent("Applications/PHP Monitor.app"))
        let marker = root.appendingPathComponent("Caches/crashed-after-bundle-move")
        let check = CrashReporter.movedBundleCheck(bundle: bundle, marker: marker)

        CrashReporter.markCrashAfterBundleMove(nil, nil, UnsafeMutableRawPointer(check))

        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func marker_applies_to_one_launch_only() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("crashed-after-bundle-move")
        FileManager.default.createFile(atPath: marker.path, contents: nil)

        #expect(CrashReporter.takeMovedBundleMarker(marker))
        #expect(!CrashReporter.takeMovedBundleMarker(marker))
    }

    // MARK: - Helpers

    private static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("crash_reporter_moved_bundle_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func makeBundle(at url: URL) throws -> URL {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data().write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }
}
