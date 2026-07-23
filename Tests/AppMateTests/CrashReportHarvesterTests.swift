import XCTest

@testable import AppMate

// The harvester is macOS-only (it reads ~/Library/Logs/DiagnosticReports),
// so the whole suite is gated the same way as the code under test.
#if os(macOS)

final class CrashReportHarvesterTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ contents: String, ageSeconds: TimeInterval = 0)
        throws
    {
        let url = dir.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        if ageSeconds != 0 {
            let date = Date().addingTimeInterval(-ageSeconds)
            try FileManager.default.setAttributes(
                [.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    func testPicksThisAppsMostRecentReport() throws {
        try write("MyApp-2026-01-01-000000.ips", "OLD CRASH", ageSeconds: 120)
        try write("MyApp-2026-02-02-000000.ips", "NEW CRASH", ageSeconds: 10)
        // Another app's crash — must be ignored.
        try write("SomeOtherApp-2026-02-03-000000.ips", "NOT MINE", ageSeconds: 1)

        let report = CrashReportHarvester.latestReport(in: dir, processName: "MyApp")
        XCTAssertEqual(report?.text, "NEW CRASH")
        XCTAssertEqual(report?.name, "MyApp-2026-02-02-000000.ips")
        XCTAssertEqual(report?.truncated, false)
    }

    func testIgnoresOtherAppsEvenIfNewer() throws {
        try write("SomeOtherApp-2026-02-03-000000.ips", "NOT MINE", ageSeconds: 1)
        XCTAssertNil(CrashReportHarvester.latestReport(in: dir, processName: "MyApp"))
    }

    func testIgnoresReportsOlderThanAWeek() throws {
        try write("MyApp-old.ips", "ANCIENT", ageSeconds: 8 * 24 * 60 * 60)
        XCTAssertNil(CrashReportHarvester.latestReport(in: dir, processName: "MyApp"))
    }

    func testIgnoresUnrelatedFileExtensions() throws {
        try write("MyApp-notes.txt", "NOT A CRASH", ageSeconds: 1)
        XCTAssertNil(CrashReportHarvester.latestReport(in: dir, processName: "MyApp"))
    }

    func testAcceptsLegacyCrashExtension() throws {
        try write("MyApp_2026.crash", "LEGACY", ageSeconds: 5)
        let report = CrashReportHarvester.latestReport(in: dir, processName: "MyApp")
        XCTAssertEqual(report?.text, "LEGACY")
    }

    func testTruncatesOversizeReportAndKeepsTheFront() throws {
        // Header at the very top (what we must keep) + filler beyond the budget.
        let header = "EXCEPTION_TYPE: EXC_BAD_ACCESS\nCrashed Thread: 0\n"
        let big = header + String(repeating: "x", count: CrashReportHarvester.maxBytes)
        try write("MyApp-big.ips", big, ageSeconds: 5)

        let report = try XCTUnwrap(
            CrashReportHarvester.latestReport(in: dir, processName: "MyApp"))
        XCTAssertTrue(report.truncated)
        XCTAssertTrue(report.text.hasPrefix(header), "front (the diagnostic part) kept")
        XCTAssertTrue(report.text.contains("truncated by AppMate"))
        // Comfortably bounded (budget + the short truncation note).
        XCTAssertLessThan(report.text.utf8.count, CrashReportHarvester.maxBytes + 200)
    }

    func testDirWithNoMatchingReportsReturnsNil() throws {
        XCTAssertNil(CrashReportHarvester.latestReport(in: dir, processName: "MyApp"))
    }
}

#endif
