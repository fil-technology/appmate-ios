import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// CrashMonitor — best-effort capture of uncaught crashes so the app can offer
// a pre-filled crash report on the NEXT launch. Two capture paths:
//
//   1. Uncaught NSExceptions — the handler runs as ordinary code, so we can
//      serialize a full record (name + reason + call stack) with JSONEncoder.
//   2. Fatal signals (SIGSEGV & friends) — the handler must stay
//      async-signal-safe, so each signal's complete JSON payload is
//      pre-serialized into a raw buffer at install time and the handler only
//      calls open/write/close (all on the POSIX async-signal-safe list). The
//      payload carries no timestamp; the loader falls back to the file's
//      mtime, which IS the crash time.
//
// Deliberately not a full crash reporter (no symbolication, no mach exception
// handling, nothing uploads by itself) — it exists to power the "we noticed a
// crash last time, want to tell us about it?" prompt.
// ─────────────────────────────────────────────────────────────────────────────

/// Persisted crash record. `crashedAt` is nil in signal payloads (filled from
/// the file's mtime at load).
struct PendingCrash: Codable {
    var exceptionName: String?
    var exceptionReason: String?
    var stackTrace: String?
    var platform: String?
    var osVersion: String?
    var deviceModel: String?
    var appVersion: String?
    var buildNumber: String?
    var crashedAt: Date?
}

/// Device/OS/app snapshot helpers shared by the monitor and
/// `CrashDiagnostics.current()`.
enum CrashDeviceInfo {
    static var platform: String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Hardware identifier — "iPhone16,2" on iOS, "Mac15,6" on macOS.
    static var deviceModel: String? {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { buf in
            String(decoding: buf.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return machine.isEmpty ? nil : machine
        #elseif os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
        #else
        return nil
        #endif
    }

    static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    static var buildNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}

// Globals the signal handler reads. Plain arrays of raw bytes/ints set once at
// install and never mutated after — the handler does index math + syscalls
// only. `nonisolated(unsafe)` matches the SDK's install-once convention
// (ShakeDetector, RetentionFlow._config).
nonisolated(unsafe) private var amCrashPathC: [CChar] = []
nonisolated(unsafe) private var amSignalNumbers: [Int32] = []
nonisolated(unsafe) private var amSignalPayloads: [[UInt8]] = []

// @convention(c) — no captures allowed; everything comes from the globals.
private func amSignalHandler(_ sig: Int32) {
    var index = -1
    for i in 0..<amSignalNumbers.count where amSignalNumbers[i] == sig {
        index = i
        break
    }
    if index >= 0, !amCrashPathC.isEmpty {
        amCrashPathC.withUnsafeBufferPointer { path in
            guard let base = path.baseAddress else { return }
            let fd = open(base, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            guard fd >= 0 else { return }
            amSignalPayloads[index].withUnsafeBufferPointer { buf in
                if let p = buf.baseAddress { _ = write(fd, p, buf.count) }
            }
            close(fd)
        }
    }
    // Restore the default action and re-raise so the process still dies the
    // way the OS expects (crash log, exit status, debugger behaviour).
    signal(sig, SIG_DFL)
    raise(sig)
}

enum CrashMonitor {
    nonisolated(unsafe) private static var installed = false
    nonisolated(unsafe) private static var previousExceptionHandler:
        (@convention(c) (NSException) -> Void)?

    /// Signals worth capturing. SIGTRAP covers Swift runtime traps
    /// (force-unwrap, array OOB) on arm64; SIGABRT covers assertion aborts.
    private static let capturedSignals: [Int32] = [
        SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP,
    ]

    /// Application Support/AppMate/pending-crash.json — survives relaunches,
    /// excluded from nothing (it's tiny and short-lived).
    static var fileURL: URL {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("AppMate", isDirectory: true)
        return dir.appendingPathComponent("pending-crash.json")
    }

    static func install() {
        guard !installed else { return }
        installed = true

        // Create the directory NOW — the handlers can't.
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 1. NSException path — chain any previously installed handler.
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            CrashMonitor.handle(exception: exception)
        }

        // 2. Signal path — pre-serialize one complete JSON payload per signal
        //    so the handler only has to write bytes.
        amCrashPathC = Array(fileURL.path.utf8CString)
        amSignalNumbers = capturedSignals
        amSignalPayloads = capturedSignals.map { sig in
            let name = signalName(sig)
            let record = PendingCrash(
                exceptionName: name,
                exceptionReason: "The app was terminated by signal \(name).",
                stackTrace: nil,
                platform: CrashDeviceInfo.platform,
                osVersion: CrashDeviceInfo.osVersion,
                deviceModel: CrashDeviceInfo.deviceModel,
                appVersion: CrashDeviceInfo.appVersion,
                buildNumber: CrashDeviceInfo.buildNumber,
                crashedAt: nil
            )
            let data = (try? JSONEncoder().encode(record)) ?? Data()
            return [UInt8](data)
        }
        for sig in capturedSignals {
            signal(sig, amSignalHandler)
        }
    }

    private static func handle(exception: NSException) {
        let record = PendingCrash(
            exceptionName: exception.name.rawValue,
            exceptionReason: exception.reason,
            stackTrace: exception.callStackSymbols.joined(separator: "\n"),
            platform: CrashDeviceInfo.platform,
            osVersion: CrashDeviceInfo.osVersion,
            deviceModel: CrashDeviceInfo.deviceModel,
            appVersion: CrashDeviceInfo.appVersion,
            buildNumber: CrashDeviceInfo.buildNumber,
            crashedAt: Date()
        )
        store(record)
        previousExceptionHandler?(exception)
    }

    /// Persist a record. Also used by tests.
    static func store(_ record: PendingCrash) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }

    /// Read the stored crash, if any. Signal payloads carry no timestamp —
    /// substitute the file's mtime (= the moment the handler wrote it).
    static func load() -> PendingCrash? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard var record = try? JSONDecoder().decode(PendingCrash.self, from: data)
        else {
            // Unreadable garbage — drop it so we don't re-offer it forever.
            clear()
            return nil
        }
        if record.crashedAt == nil {
            record.crashedAt =
                (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[
                    .modificationDate] as? Date
        }
        return record
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func signalName(_ sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT"
        case SIGILL: return "SIGILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGFPE: return "SIGFPE"
        case SIGBUS: return "SIGBUS"
        case SIGTRAP: return "SIGTRAP"
        default: return "SIG\(sig)"
        }
    }
}
