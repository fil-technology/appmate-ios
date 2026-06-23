#if canImport(SwiftUI)
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ReportView — a ready-made NATIVE report form (iOS + macOS): pick a category,
// describe the issue, optionally leave an email. Renders the published report
// config (category list + fields) and submits via the public API.
//
//     ReportView(userId: currentUser?.id) { /* submitted */ }
//
// Embed it, or use RetentionFlow.presentReport(...) to pop it as a sheet/window.
// Requires RetentionFlow.configure(_:). iOS 16+ / macOS 13+.
// ─────────────────────────────────────────────────────────────────────────────

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ReportStore: ObservableObject {
    @Published var form: ReportForm?
    @Published var loadError: String?
    @Published var submitting = false
    @Published var submitError: String?
    @Published var submitted = false

    @Published var categoryId = ""
    @Published var message = ""
    @Published var email = ""

    private let flowSlug: String?
    init(flowSlug: String?) { self.flowSlug = flowSlug }

    func load() async {
        loadError = nil
        do {
            form = try await RetentionFlow.reportForm(flowSlug: flowSlug)
        } catch {
            loadError =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    var canSubmit: Bool {
        guard let cfg = form?.config else { return false }
        if categoryId.isEmpty { return false }
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
            try await RetentionFlow.submitReport(
                category: categoryId,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                email: cfg.emailField?.enabled == true ? email : nil,
                flowSlug: form?.flowSlug
            )
            submitted = true
        } catch {
            submitError =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        submitting = false
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct ReportView: View {
    @StateObject private var store: ReportStore
    private let onSubmitted: (() -> Void)?

    public init(
        userId: String? = nil,
        flowSlug: String? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        _ = userId
        _store = StateObject(wrappedValue: ReportStore(flowSlug: flowSlug))
        self.onSubmitted = onSubmitted
    }

    private var accent: Color {
        store.form?.config.hero?.accentColor.flatMap(Color.init(amHex:)) ?? .accentColor
    }

    public var body: some View {
        ScrollView {
            if store.submitted {
                ReportSuccessCard(config: store.form?.config.success, accent: accent)
                    .padding(20)
            } else if let form = store.form {
                formBody(form.config).padding(20)
            } else if let err = store.loadError {
                VStack { ReportErrorState(message: err) { Task { await store.load() } } }
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                VStack { ProgressView() }.frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .task { if store.form == nil { await store.load() } }
        .onChange(of: store.submitted) { done in if done { onSubmitted?() } }
    }

    @ViewBuilder private func formBody(_ cfg: ReportConfig) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(cfg.intro.title).font(.title2).bold()
                if !cfg.intro.subtitle.isEmpty {
                    Text(cfg.intro.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            ReportCard {
                CategoryPicker(
                    categories: cfg.categories,
                    selected: $store.categoryId,
                    accent: accent
                )
            }

            ReportCard {
                ReportMessageEditor(
                    text: $store.message,
                    placeholder: cfg.intro.messagePlaceholder
                )
            }

            if cfg.emailField?.enabled == true {
                ReportCard {
                    ReportEmailField(
                        text: $store.email,
                        placeholder: cfg.emailField?.placeholder ?? "you@example.com"
                    )
                }
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

// MARK: - Pieces (file-private; report renders a category list, no rating)

@available(iOS 16.0, macOS 13.0, *)
private struct CategoryPicker: View {
    let categories: [ReportConfig.Category]
    @Binding var selected: String
    let accent: Color
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { idx, cat in
                Button {
                    selected = cat.id
                } label: {
                    HStack(spacing: 10) {
                        if let emoji = cat.emoji, !emoji.isEmpty { Text(emoji) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cat.label)
                                .foregroundStyle(.primary)
                            if selected == cat.id, let hint = cat.hint, !hint.isEmpty {
                                Text(hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selected == cat.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < categories.count - 1 {
                    Divider()
                }
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct ReportCard<Content: View>: View {
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
private struct ReportMessageEditor: View {
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
private struct ReportEmailField: View {
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
private struct ReportSuccessCard: View {
    let config: ReportConfig.Success?
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
private struct ReportErrorState: View {
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
