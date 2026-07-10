import XCTest

@testable import AppMate

final class CrashReportTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CrashMonitor.clear()
    }

    override func tearDown() {
        CrashMonitor.clear()
        super.tearDown()
    }

    // MARK: Config decoding

    func testDecodesCrashConfigEnvelope() throws {
        let json = """
            {
              "flowSlug": "crash",
              "app": { "name": "Demo", "logoUrl": null, "websiteUrl": "https://demo.app" },
              "config": {
                "type": "crash",
                "intro": {
                  "title": "Report a crash",
                  "subtitle": "Tell us what happened.",
                  "messagePlaceholder": "What were you doing?",
                  "submitLabel": "Send crash report",
                  "legal": "Reports may include device details."
                },
                "logField": { "enabled": true, "label": "Crash log", "placeholder": "Paste here" },
                "emailField": { "enabled": true, "placeholder": "you@example.com", "required": false },
                "success": { "title": "Received.", "body": "Thanks!" },
                "colorScheme": "dark",
                "hero": { "accentColor": "#FF6B6B" }
              }
            }
            """.data(using: .utf8)!

        struct Envelope: Decodable {
            let flowSlug: String
            let app: FeedbackBrand
            let config: CrashConfig
        }
        let env = try JSONDecoder().decode(Envelope.self, from: json)
        XCTAssertEqual(env.flowSlug, "crash")
        XCTAssertEqual(env.app.name, "Demo")
        XCTAssertEqual(env.config.intro.title, "Report a crash")
        XCTAssertEqual(env.config.logField?.enabled, true)
        XCTAssertEqual(env.config.emailField?.required, false)
        XCTAssertEqual(env.config.colorScheme, "dark")
        XCTAssertEqual(env.config.hero?.accentColor, "#FF6B6B")
    }

    func testDecodesMinimalCrashConfig() throws {
        // Optional blocks omitted entirely — the decoder must not require them.
        let json = """
            {
              "intro": {
                "title": "Report a crash",
                "subtitle": "",
                "messagePlaceholder": "What happened?",
                "submitLabel": "Send",
                "legal": null
              },
              "success": { "title": "Thanks", "body": "", "ctaLabel": null, "ctaUrl": null },
              "colorScheme": null,
              "hero": null,
              "logField": null,
              "emailField": null
            }
            """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(CrashConfig.self, from: json)
        XCTAssertNil(cfg.logField)
        XCTAssertNil(cfg.emailField)
        XCTAssertEqual(cfg.intro.submitLabel, "Send")
    }

    // MARK: Diagnostics

    func testCurrentDiagnosticsCarryDeviceInfo() {
        let d = CrashDiagnostics.current()
        #if os(iOS)
        XCTAssertEqual(d.platform, "ios")
        #elseif os(macOS)
        XCTAssertEqual(d.platform, "macos")
        #endif
        // OS version is always resolvable; the rest is best-effort but should
        // exist in a test bundle environment.
        XCTAssertFalse(d.osVersion?.isEmpty ?? true)
        XCTAssertNil(d.exceptionName, "a fresh snapshot must not claim a crash")
        XCTAssertNil(d.stackTrace)
    }

    // MARK: Pending-crash persistence

    func testStoreLoadClearRoundtrip() throws {
        let crashedAt = Date(timeIntervalSince1970: 1_751_900_000)
        CrashMonitor.store(
            PendingCrash(
                exceptionName: "NSInvalidArgumentException",
                exceptionReason: "unrecognized selector",
                stackTrace: "0 Demo 0x0000 main + 0",
                platform: "ios",
                osVersion: "17.4.1",
                deviceModel: "iPhone16,2",
                appVersion: "1.2.0",
                buildNumber: "421",
                crashedAt: crashedAt
            ))

        let loaded = try XCTUnwrap(CrashMonitor.load())
        XCTAssertEqual(loaded.exceptionName, "NSInvalidArgumentException")
        XCTAssertEqual(loaded.exceptionReason, "unrecognized selector")
        XCTAssertEqual(loaded.stackTrace, "0 Demo 0x0000 main + 0")
        XCTAssertEqual(loaded.deviceModel, "iPhone16,2")
        XCTAssertEqual(
            loaded.crashedAt?.timeIntervalSince1970 ?? 0,
            crashedAt.timeIntervalSince1970,
            accuracy: 1
        )

        CrashMonitor.clear()
        XCTAssertNil(CrashMonitor.load())
    }

    func testLoadFillsMissingCrashedAtFromFileDate() throws {
        // Signal-path records carry no timestamp; load() must substitute the
        // file's mtime (≈ now, since we just wrote it).
        CrashMonitor.store(
            PendingCrash(
                exceptionName: "SIGSEGV",
                exceptionReason: "The app was terminated by signal SIGSEGV.",
                stackTrace: nil,
                platform: "ios",
                osVersion: "17.4.1",
                deviceModel: nil,
                appVersion: nil,
                buildNumber: nil,
                crashedAt: nil
            ))
        let loaded = try XCTUnwrap(CrashMonitor.load())
        let crashedAt = try XCTUnwrap(loaded.crashedAt)
        XCTAssertEqual(crashedAt.timeIntervalSinceNow, 0, accuracy: 30)
    }

    func testLoadDropsCorruptRecord() throws {
        try FileManager.default.createDirectory(
            at: CrashMonitor.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json at all".utf8).write(to: CrashMonitor.fileURL)
        XCTAssertNil(CrashMonitor.load())
        // The corrupt file must have been swept so it isn't re-offered.
        XCTAssertFalse(FileManager.default.fileExists(atPath: CrashMonitor.fileURL.path))
    }

    // MARK: pendingCrash bridge

    func testPendingCrashMapsToDiagnostics() throws {
        CrashMonitor.store(
            PendingCrash(
                exceptionName: "SIGABRT",
                exceptionReason: "The app was terminated by signal SIGABRT.",
                stackTrace: nil,
                platform: "macos",
                osVersion: "14.5.0",
                deviceModel: "Mac15,6",
                appVersion: "2.0.0",
                buildNumber: "77",
                crashedAt: Date()
            ))
        let diag = try XCTUnwrap(RetentionFlow.pendingCrash)
        XCTAssertEqual(diag.exceptionName, "SIGABRT")
        XCTAssertEqual(diag.deviceModel, "Mac15,6")

        RetentionFlow.clearPendingCrash()
        XCTAssertNil(RetentionFlow.pendingCrash)
    }

    // MARK: Submit body

    func testSubmitBodyEncodesDiagnosticsAndSource() throws {
        let body = RetentionFlow.SubmitCrashBody(
            appSlug: "demo",
            flowSlug: nil,
            message: "It crashed on launch",
            email: nil,
            source: "sdk_auto",
            diagnostics: CrashDiagnostics(
                exceptionName: "SIGTRAP",
                stackTrace: "frame 0",
                platform: "ios",
                osVersion: "17.0.0",
                crashedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        let data = try JSONEncoder().encode(body)
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["appSlug"] as? String, "demo")
        XCTAssertEqual(obj["source"] as? String, "sdk_auto")
        XCTAssertEqual(obj["exceptionName"] as? String, "SIGTRAP")
        XCTAssertEqual(obj["crashedAt"] as? Int, 1_700_000_000_000)
        // Optional fields that are nil must be omitted or null — either is
        // fine for the server; assert no bogus values leak in.
        XCTAssertNil(obj["email"] as? String)
        // No attachments passed → key omitted entirely.
        XCTAssertNil(obj["attachments"])
    }

    // MARK: Attachments

    func testSubmitBodyEncodesAttachmentsAsNameContent() throws {
        let body = RetentionFlow.SubmitCrashBody(
            appSlug: "demo",
            flowSlug: nil,
            message: "froze",
            email: nil,
            source: "sdk",
            diagnostics: .current(),
            attachments: [
                CrashAttachment(name: "console.log", text: "line 1\nline 2"),
                CrashAttachment(name: "breadcrumbs", text: "tapped export"),
                // Empty text must be dropped, not sent as an empty attachment.
                CrashAttachment(name: "empty", text: ""),
            ]
        )
        let data = try JSONEncoder().encode(body)
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        let atts = try XCTUnwrap(obj["attachments"] as? [[String: Any]])
        XCTAssertEqual(atts.count, 2, "empty-text attachment should be dropped")
        XCTAssertEqual(atts[0]["name"] as? String, "console.log")
        XCTAssertEqual(atts[0]["content"] as? String, "line 1\nline 2")
        XCTAssertEqual(atts[1]["name"] as? String, "breadcrumbs")
    }

    func testAttachmentFromFileReadsAndTruncates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("am-crash-att-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("app.log")
        try String(repeating: "x", count: 5000).write(to: url, atomically: true, encoding: .utf8)

        let att = try XCTUnwrap(CrashAttachment.file(named: "app.log", at: url, maxBytes: 1024))
        XCTAssertEqual(att.name, "app.log")
        XCTAssertEqual(att.text.count, 1024, "content should be truncated to maxBytes")

        // Missing file → nil (so callers can compactMap).
        XCTAssertNil(
            CrashAttachment.file(named: "missing", at: dir.appendingPathComponent("nope.log")))
    }
}
