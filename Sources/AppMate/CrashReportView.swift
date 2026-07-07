#if canImport(SwiftUI)
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// CrashReportView — a ready-made NATIVE crash-report form (iOS + macOS):
// describe what happened, optionally leave an email. Device/OS/app diagnostics
// are attached automatically (with a visible summary + opt-out toggle). When a
// crash was captured on the previous run (``RetentionFlow/enableCrashDetection()``)
// the form pre-fills that capture and clears it after a successful submit.
//
//     CrashReportView(userId: currentUser?.id) { /* submitted */ }
//
// Embed it, or use RetentionFlow.presentCrashReport(...) to pop it as a
// sheet/window. Requires RetentionFlow.configure(_:). iOS 16+ / macOS 13+.
// ─────────────────────────────────────────────────────────────────────────────

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class CrashReportStore: ObservableObject {
    @Published var form: CrashForm?
    @Published var loadError: String?
    @Published var submitting = false
    @Published var submitError: String?
    @Published var submitted = false

    @Published var message = ""
    @Published var email = ""
    @Published var includeDiagnostics = true

    let diagnostics: CrashDiagnostics
    /// Whether `diagnostics` came from a crash captured on a previous run
    /// (vs a fresh device snapshot). Captured crashes are cleared on submit.
    let fromPendingCrash: Bool

    private let flowSlug: String?

    init(flowSlug: String?) {
        self.flowSlug = flowSlug
        if let pending = RetentionFlow.pendingCrash {
            diagnostics = pending
            fromPendingCrash = true
        } else {
            diagnostics = .current()
            fromPendingCrash = false
        }
    }

    func load() async {
        loadError = nil
        do {
            form = try await RetentionFlow.crashReportForm(flowSlug: flowSlug)
        } catch {
            loadError =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    var canSubmit: Bool {
        guard let cfg = form?.config else { return false }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if cfg.emailField?.required == true
            && email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return false
        }
        return true
    }

    func submit() async {
        guard let cfg = form?.config else { return }
        submitting = true
        submitError = nil
        do {
            try await RetentionFlow.submitCrashReport(
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                email: cfg.emailField?.enabled == true ? email : nil,
                diagnostics: includeDiagnostics ? diagnostics : nil,
                flowSlug: form?.flowSlug
            )
            if fromPendingCrash { RetentionFlow.clearPendingCrash() }
            submitted = true
        } catch {
            submitError =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct CrashReportView: View {
    @StateObject private var store: CrashReportStore
    private let onSubmitted: (() -> Void)?

    public init(
        userId: String? = nil,
        flowSlug: String? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        _ = userId
        _store = StateObject(wrappedValue: CrashReportStore(flowSlug: flowSlug))
        self.onSubmitted = onSubmitted
    }

    private var accent: Color {
        store.form?.config.hero?.accentColor.flatMap(Color.init(amHex:)) ?? .accentColor
    }

    public var body: some View {
        ScrollView {
            if store.submitted {
                CrashSuccessCard(config: store.form?.config.success, accent: accent)
                    .padding(20)
            } else if let form = store.form {
                formBody(form.config).padding(20)
            } else if let err = store.loadError {
                VStack { CrashErrorState(message: err) { Task { await store.load() } } }
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                VStack { ProgressView() }.frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .task { if store.form == nil { await store.load() } }
        .onChange(of: store.submitted) { done in if done { onSubmitted?() } }
    }

    @ViewBuilder private func formBody(_ cfg: CrashConfig) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(cfg.intro.title).font(.title2).bold()
                if !cfg.intro.subtitle.isEmpty {
                    Text(cfg.intro.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if store.fromPendingCrash {
                CrashCapturedBanner(diagnostics: store.diagnostics, accent: accent)
            }

            CrashCard {
                CrashMessageEditor(
                    text: $store.message,
                    placeholder: cfg.intro.messagePlaceholder
                )
            }

            if cfg.emailField?.enabled == true {
                CrashCard {
                    CrashEmailField(
                        text: $store.email,
                        placeholder: cfg.emailField?.placeholder ?? "you@example.com"
                    )
                }
            }

            CrashCard {
                CrashDiagnosticsSection(
                    diagnostics: store.diagnostics,
                    include: $store.includeDiagnostics
                )
            }

            if let submitError = store.submitError {
                Text(submitError).font(.footnote).foregroundStyle(.red)
            }

            Button {
                Task { await store.submit() }
            } label: {
                HStack {
                    Spacer()
                    if store.submitting { ProgressView() } else {
                        Text(cfg.intro.submitLabel).bold()
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .background(store.canSubmit ? accent : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(!store.canSubmit || store.submitting)

            if let legal = cfg.intro.legal, !legal.isEmpty {
                Text(legal)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - Pieces (file-private)

/// "We noticed the app crashed last time" callout shown when the form was
/// opened with a captured crash pending.
@available(iOS 16.0, macOS 13.0, *)
private struct CrashCapturedBanner: View {
    let diagnostics: CrashDiagnostics
    let accent: Color
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("We noticed the app crashed last time.")
                    .font(.footnote.weight(.semibold))
                if let name = diagnostics.exceptionName {
                    Text(name)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct CrashDiagnosticsSection: View {
    let diagnostics: CrashDiagnostics
    @Binding var include: Bool

    private var summary: String {
        var parts: [String] = []
        if let model = diagnostics.deviceModel { parts.append(model) }
        if let os = diagnostics.osVersion {
            parts.append("\(diagnostics.platform == "macos" ? "macOS" : "iOS") \(os)")
        }
        if let v = diagnostics.appVersion {
            parts.append("v\(v)\(diagnostics.buildNumber.map { " (\($0))" } ?? "")")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $include) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include diagnostics")
                        .font(.subheadline.weight(.medium))
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if include, let trace = diagnostics.stackTrace, !trace.isEmpty {
                DisclosureGroup {
                    ScrollView(.horizontal) {
                        Text(trace)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                } label: {
                    Text("Stack trace")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct CrashCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct CrashMessageEditor: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct CrashEmailField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        let field = TextField(placeholder, text: $text)
        #if os(iOS)
        field
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        field
        #endif
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct CrashSuccessCard: View {
    let config: CrashConfig.Success?
    let accent: Color
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(accent)
            }
            Text(config?.title ?? "Thanks!").font(.title3).bold()
                .multilineTextAlignment(.center)
            if let body = config?.body, !body.isEmpty {
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let label = config?.ctaLabel, !label.isEmpty,
                let urlStr = config?.ctaUrl, let url = URL(string: urlStr)
            {
                Link(label, destination: url)
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct CrashErrorState: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
        }
        .padding(24)
    }
}
#endif
