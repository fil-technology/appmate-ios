import Foundation

// Harvests the OS-written crash report for THIS app on macOS.
//
// The SDK's own CrashMonitor captures an in-process backtrace — useful, but
// unsymbolicated and missing the register state, thread list, and binary
// images that make a crash actually diagnosable. macOS writes a far richer
// report to ~/Library/Logs/DiagnosticReports/ the next time it can, named
// `<ProcessName>-<timestamp>.ips` (modern) or `.crash` (older). This reads the
// app's OWN most-recent one so it can be attached to a crash report.
//
// Reading only our own process's reports is deliberate: a Mac's
// DiagnosticReports folder contains crashes for MANY apps, and this SDK has no
// business shipping another vendor's crash off the user's machine.
//
// macOS only. The whole file is behind `#if os(macOS)`; the public entry point
// on other platforms simply returns nil.

#if os(macOS)

enum CrashReportHarvester {
    // Server clamps each attachment to 32 KB, so we stay just under it. The
    // exception summary, termination reason, and crashed-thread backtrace all
    // sit at the TOP of both .ips and .crash formats — so when a report is
    // larger than this, keeping the FRONT preserves what crashed and where and
    // drops the binary-image list (symbolication data) at the tail. That's the
    // right thing to lose under a byte budget.
    static let maxBytes = 30 * 1024

    // Ignore anything older than this — a week-old report almost certainly
    // isn't the crash the user is reporting now, and re-surfacing stale ones
    // is worse than surfacing none.
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    // Remembers the last report we already sent, so enabling silent auto-report
    // doesn't re-upload the same crash on every launch.
    private static let sentKey = "com.appmate.crash.lastHarvestedReport"

    struct Report {
        let name: String // filename, used both as the attachment label and dedup id
        let text: String
        let truncated: Bool
        let modifiedAt: Date
    }

    /// The app's own most-recent crash report, or nil when there isn't one we
    /// can read. Does NOT consult the sent-marker — callers that want
    /// dedup use `unsentReport()`.
    static func latestReport() -> Report? {
        guard let dir = diagnosticReportsDir() else { return nil }
        return latestReport(in: dir, processName: ProcessInfo.processInfo.processName)
    }

    // Testable core: directory + process name injected so the selection,
    // filtering, budget, and truncation logic can be exercised against a temp
    // folder without a real crash.
    static func latestReport(in dir: URL, processName procName: String) -> Report? {
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return nil }

        let cutoff = Date().addingTimeInterval(-maxAge)

        let mine =
            entries
            .filter { url in
                let ext = url.pathExtension.lowercased()
                guard ext == "ips" || ext == "crash" else { return false }
                // macOS prefixes the filename with the process name; the
                // separator is "-" for .ips and "_" for some .crash variants.
                let base = url.lastPathComponent
                return base.hasPrefix("\(procName)-")
                    || base.hasPrefix("\(procName)_")
            }
            .compactMap { url -> (URL, Date)? in
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                guard let mod, mod >= cutoff else { return nil }
                return (url, mod)
            }
            .sorted { $0.1 > $1.1 }

        guard let (url, mod) = mine.first else { return nil }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }

        let truncated = data.count > maxBytes
        let slice = truncated ? data.prefix(maxBytes) : data
        guard var text = String(data: slice, encoding: .utf8), !text.isEmpty else {
            return nil
        }
        if truncated {
            text += "\n\n[truncated by AppMate — \(data.count / 1024) KB total; "
                + "binary-image list omitted]"
        }

        return Report(
            name: url.lastPathComponent,
            text: text,
            truncated: truncated,
            modifiedAt: mod
        )
    }

    /// The latest report, but only if we haven't already sent it. Marks it sent
    /// as a side effect so a second call in the same session returns nil.
    static func unsentReport() -> Report? {
        guard let report = latestReport() else { return nil }
        let sent = UserDefaults.standard.string(forKey: sentKey)
        guard report.name != sent else { return nil }
        UserDefaults.standard.set(report.name, forKey: sentKey)
        return report
    }

    // ~/Library/Logs/DiagnosticReports. Inside a sandbox this resolves into the
    // app container (and is usually empty); try? handles the not-permitted
    // case by yielding nil, so the caller degrades to the in-process backtrace.
    private static func diagnosticReportsDir() -> URL? {
        guard
            let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
                .first
        else { return nil }
        let dir = lib.appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
            isDir.boolValue
        else { return nil }
        return dir
    }
}

#endif
