import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Native crash-report flow — typed config + submit, so clients can render the
// crash form natively (see CrashReportView / RetentionFlow.presentCrashReport)
// instead of the hosted web page. The web flow remains an option; this is
// additive.
//
// Crash report = describe what happened (required) + optionally leave an
// email, with a structured diagnostics block (exception, stack trace,
// device/OS/app versions) attached automatically. Pair with
// ``RetentionFlow/enableCrashDetection()`` to capture uncaught crashes and
// offer them for submission on the next launch.
// ─────────────────────────────────────────────────────────────────────────────

public struct CrashConfig: Decodable, Sendable {
    public struct Intro: Decodable, Sendable {
        public let title: String
        public let subtitle: String
        public let messagePlaceholder: String
        public let submitLabel: String
        public let legal: String?
    }
    /// Hosted-page-only "paste a log" textarea. The native form ignores it —
    /// the SDK sends real diagnostics in the structured fields instead.
    public struct LogField: Decodable, Sendable {
        public let enabled: Bool
        public let label: String?
        public let placeholder: String?
    }
    public struct EmailField: Decodable, Sendable {
        public let enabled: Bool
        public let placeholder: String?
        public let required: Bool?
    }
    public struct Success: Decodable, Sendable {
        public let title: String
        public let body: String
        public let ctaLabel: String?
        public let ctaUrl: String?
    }
    public struct Hero: Decodable, Sendable {
        public let accentColor: String?
    }

    public let intro: Intro
    public let logField: LogField?
    public let emailField: EmailField?
    public let success: Success
    public let colorScheme: String?
    public let hero: Hero?
}

/// Config + brand for rendering a native crash-report form. Reuses
/// ``FeedbackBrand`` (just the app's name/logo/website — same shape for every
/// flow).
public struct CrashForm: Sendable {
    public let flowSlug: String
    public let app: FeedbackBrand
    public let config: CrashConfig
}

public enum CrashReportError: Error, LocalizedError {
    case notConfigured
    case notOpen
    case http(status: Int, body: String?)
    case transport(Error)
    case decode(Error)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "RetentionFlow.configure(_:) must be called first."
        case .notOpen:
            return "This crash flow isn't published yet."
        case .http(let status, let body):
            return "Crash report request failed (\(status)): \(body ?? "no body")"
        case .transport(let err):
            return "Network error: \(err.localizedDescription)"
        case .decode(let err):
            return "Couldn't read the crash flow config: \(err.localizedDescription)"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostics — the structured block attached to a crash report.
// ─────────────────────────────────────────────────────────────────────────────

/// Structured diagnostics attached to a crash report. Build one with
/// ``current()`` (device/OS/app info, no exception), take the captured one
/// from ``RetentionFlow/pendingCrash``, or fill the fields yourself.
public struct CrashDiagnostics: Sendable {
    /// e.g. `NSInvalidArgumentException` or `SIGSEGV`.
    public var exceptionName: String?
    public var exceptionReason: String?
    public var stackTrace: String?
    public var platform: String?
    public var osVersion: String?
    public var deviceModel: String?
    public var appVersion: String?
    public var buildNumber: String?
    /// When the crash happened. For a captured crash this is the moment of the
    /// crash on the PREVIOUS run, not when the report is submitted.
    public var crashedAt: Date?

    public init(
        exceptionName: String? = nil,
        exceptionReason: String? = nil,
        stackTrace: String? = nil,
        platform: String? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil,
        appVersion: String? = nil,
        buildNumber: String? = nil,
        crashedAt: Date? = nil
    ) {
        self.exceptionName = exceptionName
        self.exceptionReason = exceptionReason
        self.stackTrace = stackTrace
        self.platform = platform
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.crashedAt = crashedAt
    }

    /// Best-effort snapshot of the current device/OS/app — no exception info.
    /// This is what the native form attaches for a user-initiated report.
    public static func current() -> CrashDiagnostics {
        CrashDiagnostics(
            platform: CrashDeviceInfo.platform,
            osVersion: CrashDeviceInfo.osVersion,
            deviceModel: CrashDeviceInfo.deviceModel,
            appVersion: CrashDeviceInfo.appVersion,
            buildNumber: CrashDeviceInfo.buildNumber
        )
    }

    init(from pending: PendingCrash) {
        self.init(
            exceptionName: pending.exceptionName,
            exceptionReason: pending.exceptionReason,
            stackTrace: pending.stackTrace,
            platform: pending.platform,
            osVersion: pending.osVersion,
            deviceModel: pending.deviceModel,
            appVersion: pending.appVersion,
            buildNumber: pending.buildNumber,
            crashedAt: pending.crashedAt
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attachments — small NAMED TEXT logs sent alongside a crash report (console
// output, breadcrumbs, a rolling log file, app-state dump). Text only, kept
// small so it stays inline server-side — this is not a file-upload system.
// The server clamps to 5 attachments, 32 KB each, 128 KB total.
// ─────────────────────────────────────────────────────────────────────────────

public struct CrashAttachment: Sendable {
    /// Short label shown in the dashboard (e.g. "console.log", "breadcrumbs").
    public let name: String
    /// The log text. Truncated to `maxBytes` when built from a file; the server
    /// clamps again regardless.
    public let text: String

    public init(name: String, text: String) {
        self.name = name
        self.text = text
    }

    /// Build an attachment from a small text file (e.g. your app's rolling log).
    /// Reads up to `maxBytes` of UTF-8 text; returns `nil` if the file is
    /// missing, unreadable, or empty so callers can `compactMap` safely.
    public static func file(
        named name: String,
        at url: URL,
        maxBytes: Int = 32 * 1024
    ) -> CrashAttachment? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let slice = data.count > maxBytes ? data.prefix(maxBytes) : data
        guard let text = String(data: slice, encoding: .utf8), !text.isEmpty else {
            return nil
        }
        return CrashAttachment(name: name, text: text)
    }
}

extension RetentionFlow {

    private struct CrashConfigEnvelope: Decodable {
        let flowSlug: String
        let app: FeedbackBrand
        let config: CrashConfig
    }

    /// Fetch the published crash-flow config + brand so you can render the
    /// form natively. `flowSlug` targets a non-primary crash flow (omit for
    /// the primary). Throws `CrashReportError.notOpen` if it isn't published.
    public static func crashReportForm(flowSlug: String? = nil) async throws -> CrashForm {
        guard let config = config else { throw CrashReportError.notConfigured }
        var comps = URLComponents(
            url: config.baseURL.appendingPathComponent("api/public/crash"),
            resolvingAgainstBaseURL: false
        )
        var items = [URLQueryItem(name: "appSlug", value: config.appSlug)]
        if let flowSlug, !flowSlug.isEmpty {
            items.append(URLQueryItem(name: "flowSlug", value: flowSlug))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { throw CrashReportError.notOpen }

        var req = URLRequest(url: url)
        req.timeoutInterval = config.requestTimeout
        req.addValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw CrashReportError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 404 { throw CrashReportError.notOpen }
        guard (200..<300).contains(status) else {
            throw CrashReportError.http(
                status: status, body: String(data: data, encoding: .utf8))
        }
        do {
            let env = try JSONDecoder().decode(CrashConfigEnvelope.self, from: data)
            return CrashForm(flowSlug: env.flowSlug, app: env.app, config: env.config)
        } catch {
            throw CrashReportError.decode(error)
        }
    }

    struct WireAttachment: Encodable {
        let name: String
        let content: String
    }

    struct SubmitCrashBody: Encodable {
        let appSlug: String
        let flowSlug: String?
        let message: String
        let email: String?
        let source: String
        let exceptionName: String?
        let exceptionReason: String?
        let stackTrace: String?
        let platform: String?
        let osVersion: String?
        let deviceModel: String?
        let appVersion: String?
        let buildNumber: String?
        /// Epoch milliseconds — the server accepts ms or an ISO string.
        let crashedAt: Int?
        /// Named text logs. Omitted from the JSON when empty.
        let attachments: [WireAttachment]?

        init(
            appSlug: String,
            flowSlug: String?,
            message: String,
            email: String?,
            source: String,
            diagnostics: CrashDiagnostics?,
            attachments: [CrashAttachment] = []
        ) {
            self.appSlug = appSlug
            self.flowSlug = flowSlug
            self.message = message
            self.email = email
            self.source = source
            self.exceptionName = diagnostics?.exceptionName
            self.exceptionReason = diagnostics?.exceptionReason
            self.stackTrace = diagnostics?.stackTrace
            self.platform = diagnostics?.platform
            self.osVersion = diagnostics?.osVersion
            self.deviceModel = diagnostics?.deviceModel
            self.appVersion = diagnostics?.appVersion
            self.buildNumber = diagnostics?.buildNumber
            self.crashedAt = diagnostics?.crashedAt.map {
                Int($0.timeIntervalSince1970 * 1000)
            }
            let wire = attachments
                .filter { !$0.text.isEmpty }
                .map { WireAttachment(name: $0.name, content: $0.text) }
            self.attachments = wire.isEmpty ? nil : wire
        }
    }

    /// Submit a crash report. `message` is the user's description (required);
    /// `diagnostics` defaults to a fresh device/OS/app snapshot — pass
    /// ``RetentionFlow/pendingCrash`` to submit a captured crash, or `nil` to
    /// send no diagnostics at all. `attachments` are small named text logs
    /// (console output, breadcrumbs, a rolling log file — see
    /// ``CrashAttachment``); the server keeps up to 5, 32 KB each. Throws on
    /// validation/network failure.
    public static func submitCrashReport(
        message: String,
        email: String? = nil,
        diagnostics: CrashDiagnostics? = .current(),
        attachments: [CrashAttachment] = [],
        flowSlug: String? = nil
    ) async throws {
        guard let config = config else { throw CrashReportError.notConfigured }
        let endpoint = config.baseURL.appendingPathComponent("api/public/crash")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = config.requestTimeout
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(
            SubmitCrashBody(
                appSlug: config.appSlug,
                flowSlug: flowSlug,
                message: message,
                email: email?.isEmpty == false ? email : nil,
                // A report that carries a captured exception came from the
                // monitor; plain reports are user-initiated.
                source: diagnostics?.exceptionName != nil ? "sdk_auto" : "sdk",
                diagnostics: diagnostics,
                attachments: attachments
            ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw CrashReportError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw CrashReportError.http(
                status: status, body: String(data: data, encoding: .utf8))
        }
    }

    // MARK: Crash detection

    /// Install the best-effort crash monitor. Call once at launch (after
    /// ``configure(_:)``). Captures uncaught NSExceptions (name + reason +
    /// call stack) and fatal signals (SIGSEGV & friends — signal name only),
    /// persists them, and exposes the record on the NEXT launch via
    /// ``pendingCrash`` so you can ask the user to submit it:
    ///
    ///     RetentionFlow.enableCrashDetection()
    ///     if RetentionFlow.pendingCrash != nil {
    ///         RetentionFlow.presentCrashReport()   // pre-fills the capture
    ///     }
    ///
    /// This is a lightweight prompt-to-report aid, not a full crash reporter —
    /// it never uploads anything by itself, and coexists with (runs before)
    /// any previously installed exception handler.
    public static func enableCrashDetection() {
        CrashMonitor.install()
    }

    /// The crash captured on a previous run, if any. Non-nil until the report
    /// is submitted via the native form or ``clearPendingCrash()`` is called.
    public static var pendingCrash: CrashDiagnostics? {
        CrashMonitor.load().map(CrashDiagnostics.init(from:))
    }

    /// Drop the stored crash record (e.g. the user declined to report it).
    public static func clearPendingCrash() {
        CrashMonitor.clear()
    }

    // MARK: System crash reports (macOS)

    /// The OS-written crash report for THIS app's most recent crash, as an
    /// attachment ready to send — or nil if there isn't one we can read.
    ///
    /// On macOS this reads the app's own newest `.ips`/`.crash` from
    /// `~/Library/Logs/DiagnosticReports/`. That report is far richer than the
    /// in-process backtrace in ``pendingCrash`` — it carries the exception
    /// type, termination reason, every thread, register state, and the binary
    /// images needed to symbolicate. On every other platform this returns nil.
    ///
    /// > Privacy: a system crash report contains absolute file paths (which
    /// > include the Mac's user name) and the app's loaded-library map. It's
    /// > more than the plain backtrace, so only attach it when that's a
    /// > trade-off you want.
    ///
    /// Reports older than a week are ignored, and a report is only returned
    /// once — a second call (or a later launch) won't hand back one already
    /// consumed, so this is safe to attach unconditionally.
    public static func latestSystemCrashReport() -> CrashAttachment? {
        #if os(macOS)
        guard let report = CrashReportHarvester.unsentReport() else { return nil }
        return CrashAttachment(name: report.name, text: report.text)
        #else
        return nil
        #endif
    }

    /// Silently report a crash captured on the previous run — no form, no user
    /// interaction. Call once at launch, right after ``enableCrashDetection()``:
    ///
    ///     RetentionFlow.enableCrashDetection()
    ///     Task { await RetentionFlow.reportPendingCrash() }
    ///
    /// It submits when there's a captured crash from ``pendingCrash`` OR (on
    /// macOS, when `includeSystemReport` is true) an unsent OS crash report —
    /// whichever exists, preferring to send both together. On success the
    /// pending record is cleared so it isn't sent twice. Returns whether
    /// anything was sent. Never throws: a background auto-report shouldn't be
    /// able to break app launch, so transport failures resolve to `false` and
    /// leave the pending record in place for a later retry.
    ///
    /// - Parameters:
    ///   - message: stored as the report body. The default marks it as
    ///     automatic so these are distinguishable from user-written reports.
    ///   - includeSystemReport: macOS only — also attach the OS crash report
    ///     (see ``latestSystemCrashReport()`` for the privacy note). Ignored
    ///     elsewhere.
    @discardableResult
    public static func reportPendingCrash(
        message: String = "Automatically reported crash.",
        includeSystemReport: Bool = true
    ) async -> Bool {
        let pending = pendingCrash
        let systemReport = includeSystemReport ? latestSystemCrashReport() : nil

        // Nothing captured and no OS report → nothing to do.
        guard pending != nil || systemReport != nil else { return false }

        do {
            try await submitCrashReport(
                message: message,
                // A pending record carries the exception so `source` becomes
                // sdk_auto; a system-report-only send still reads as automatic.
                diagnostics: pending ?? .current(),
                attachments: systemReport.map { [$0] } ?? []
            )
            if pending != nil { clearPendingCrash() }
            return true
        } catch {
            // Leave pendingCrash intact so the next launch can retry. Note the
            // system report was already marked consumed by unsentReport(); a
            // retry sends the pending backtrace without it, which is acceptable
            // — re-reading a possibly-rotated .ips isn't worth the complexity.
            return false
        }
    }
}
