import XCTest
@testable import AppMate

// Opt-in live probe: reads a REAL .ips from this machine's DiagnosticReports to
// prove the harvester parses actual OS reports, not just fixtures. Skips when
// none are present so CI on a clean box stays green.
#if os(macOS)
final class CrashHarvesterLiveTests: XCTestCase {
    func testReadsARealSystemReportIfPresent() throws {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let dir = lib.appendingPathComponent("Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        guard let sample = files.first(where: { $0.hasSuffix(".ips") }) else {
            throw XCTSkip("no .ips reports on this machine")
        }
        let proc = String(sample.split(separator: "-").first ?? "")
        let report = try XCTUnwrap(
            CrashReportHarvester.latestReport(in: dir, processName: proc),
            "should read a real report for process \(proc)")
        XCTAssertFalse(report.text.isEmpty)
        XCTAssertTrue(report.name.hasPrefix(proc))
        XCTAssertLessThanOrEqual(report.text.utf8.count, CrashReportHarvester.maxBytes + 200)
        print("LIVE: read \(report.name), \(report.text.utf8.count) bytes, truncated=\(report.truncated)")
    }
}
#endif
