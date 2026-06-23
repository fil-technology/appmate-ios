#if canImport(SwiftUI)
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// FeedbackView — a ready-made NATIVE feedback form (iOS + macOS), the native
// alternative to opening the hosted web page in a Safari sheet:
//
//     FeedbackView(userId: currentUser?.id) { /* submitted */ }
//
// It fetches the published feedback config and renders exactly what the owner
// enabled — star rating, the message field, an optional reply-email, and any
// custom fields — then submits via the public feedback API. Embed it anywhere,
// or use RetentionFlow.presentFeedback(...) to pop it as a sheet/window.
//
// Requires RetentionFlow.configure(_:). iOS 16+ / macOS 13+.
// ─────────────────────────────────────────────────────────────────────────────

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class FeedbackStore: ObservableObject {
    @Published var form: FeedbackForm?
    @Published var loadError: String?
    @Published var submitting = false
    @Published var submitError: String?
    @Published var submitted = false

    // Form state
    @Published var message = ""
    @Published var rating = 0
    @Published var email = ""
    @Published var fieldValues: [String: String] = [:]

    private let flowSlug: String?
    init(flowSlug: String?) { self.flowSlug = flowSlug }

    func load() async {
        loadError = nil
        do {
            form = try await RetentionFlow.feedbackForm(flowSlug: flowSlug)
        } catch {
            loadError =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    var canSubmit: Bool {
        guard let cfg = form?.config else { return false }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if cfg.rating?.required == true && rating == 0 { return false }
        if cfg.emailField?.required == true
            && email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return false
        }
        for f in cfg.fields ?? [] where f.required == true && f.type != "boolean" {
            if (fieldValues[f.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            {
                return false
            }
        }
        return true
    }

    func submit() async {
        guard let cfg = form?.config else { return }
        submitting = true
        submitError = nil
        do {
            try await RetentionFlow.submitFeedback(
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                rating: (cfg.rating?.enabled == true && rating > 0) ? rating : nil,
                email: cfg.emailField?.enabled == true ? email : nil,
                fields: fieldValues.isEmpty ? nil : fieldValues,
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
public struct FeedbackView: View {
    @StateObject private var store: FeedbackStore
    private let onSubmitted: (() -> Void)?

    public init(
        userId: String? = nil,
        flowSlug: String? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        // userId is accepted for API symmetry / future analytics; feedback is
        // anonymous by default so it isn't sent today.
        _ = userId
        _store = StateObject(wrappedValue: FeedbackStore(flowSlug: flowSlug))
        self.onSubmitted = onSubmitted
    }

    private var accent: Color {
        store.form?.config.hero?.accentColor.flatMap(Color.init(amHex:)) ?? .accentColor
    }

    public var body: some View {
        ScrollView {
            if store.submitted {
                SuccessCard(config: store.form?.config.success, accent: accent)
                    .padding(20)
            } else if let form = store.form {
                formBody(form.config)
                    .padding(20)
            } else if let err = store.loadError {
                centered { ErrorState(message: err) { Task { await store.load() } } }
            } else {
                centered { ProgressView() }
            }
        }
        .task { if store.form == nil { await store.load() } }
        .onChange(of: store.submitted) { done in if done { onSubmitted?() } }
    }

    @ViewBuilder private func centered<C: View>(@ViewBuilder _ content: () -> C)
        -> some View
    {
        VStack { content() }
            .frame(maxWidth: .infinity, minHeight: 280)
    }

    @ViewBuilder private func formBody(_ cfg: FeedbackConfig) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(cfg.intro.title)
                    .font(.title2).bold()
                if !cfg.intro.subtitle.isEmpty {
                    Text(cfg.intro.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if cfg.rating?.enabled == true {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        if let prompt = cfg.rating?.prompt, !prompt.isEmpty {
                            Text(prompt).font(.subheadline.weight(.medium))
                        }
                        StarRating(rating: $store.rating, accent: accent)
                    }
                }
            }

            Card {
                MessageEditor(
                    text: $store.message,
                    placeholder: cfg.intro.messagePlaceholder
                )
            }

            if cfg.emailField?.enabled == true {
                Card {
                    EmailField(
                        text: $store.email,
                        placeholder: cfg.emailField?.placeholder ?? "you@example.com"
                    )
                }
            }

            ForEach(cfg.fields ?? []) { field in
                Card { CustomFieldRow(field: field, value: bindingFor(field.id)) }
            }

            if let submitError = store.submitError {
                Text(submitError).font(.footnote).foregroundStyle(.red)
            }

            Button {
                Task { await store.submit() }
            } label: {
                HStack {
                    Spacer()
                    if store.submitting {
                        ProgressView()
                    } else {
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

    private func bindingFor(_ id: String) -> Binding<String> {
        Binding(
            get: { store.fieldValues[id] ?? "" },
            set: { store.fieldValues[id] = $0 }
        )
    }
}

// MARK: - Pieces

@available(iOS 16.0, macOS 13.0, *)
private struct Card<Content: View>: View {
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
private struct StarRating: View {
    @Binding var rating: Int
    let accent: Color
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(i <= rating ? accent : Color.secondary)
                    .onTapGesture { rating = (rating == i) ? 0 : i }
                    .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct MessageEditor: View {
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
private struct EmailField: View {
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
private struct CustomFieldRow: View {
    let field: FeedbackConfig.Field
    @Binding var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.label).font(.subheadline.weight(.medium))
            switch field.type {
            case "boolean":
                Toggle(
                    "",
                    isOn: Binding(
                        get: { value == "true" },
                        set: { value = $0 ? "true" : "false" }
                    )
                )
                .labelsHidden()
            case "select":
                Picker("", selection: $value) {
                    Text("Choose…").tag("")
                    ForEach(field.options ?? [], id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            default:
                TextField(field.placeholder ?? "", text: $value)
            }
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct SuccessCard: View {
    let config: FeedbackConfig.Success?
    let accent: Color
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 64, height: 64)
                Image(systemName: "checkmark")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(accent)
            }
            Text(config?.title ?? "Thanks!")
                .font(.title3).bold()
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
private struct ErrorState: View {
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

// Parse an "#rrggbb" hex string into a Color (cross-platform).
extension Color {
    init?(amHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
#endif
