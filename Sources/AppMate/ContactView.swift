#if canImport(SwiftUI)
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ContactView — a ready-made NATIVE contact form (iOS + macOS): name / email /
// message, each shown only if the flow enables it, plus any custom fields.
//
//     ContactView(userId: currentUser?.id) { /* submitted */ }
//
// Embed it, or use RetentionFlow.presentContact(...) to pop a sheet/window.
// Requires RetentionFlow.configure(_:). iOS 16+ / macOS 13+.
// ─────────────────────────────────────────────────────────────────────────────

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ContactStore: ObservableObject {
    @Published var form: ContactForm?
    @Published var loadError: String?
    @Published var submitting = false
    @Published var submitError: String?
    @Published var submitted = false

    @Published var name = ""
    @Published var email = ""
    @Published var message = ""
    @Published var fieldValues: [String: String] = [:]

    private let flowSlug: String?
    init(flowSlug: String?) { self.flowSlug = flowSlug }

    func load() async {
        loadError = nil
        do {
            form = try await RetentionFlow.contactForm(flowSlug: flowSlug)
        } catch {
            loadError =
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func empty(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmit: Bool {
        guard let cfg = form?.config else { return false }
        if cfg.nameField?.required == true && empty(name) { return false }
        if cfg.emailField?.required == true && empty(email) { return false }
        if cfg.messageField?.required == true && empty(message) { return false }
        for f in cfg.fields ?? [] where f.required == true && f.type != "boolean" {
            if empty(fieldValues[f.id] ?? "") { return false }
        }
        return true
    }

    func submit() async {
        guard let cfg = form?.config else { return }
        submitting = true
        submitError = nil
        do {
            try await RetentionFlow.submitContact(
                name: cfg.nameField?.enabled == true ? name : nil,
                email: cfg.emailField?.enabled == true ? email : nil,
                message: cfg.messageField?.enabled == true ? message : nil,
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
public struct ContactView: View {
    @StateObject private var store: ContactStore
    private let onSubmitted: (() -> Void)?

    public init(
        userId: String? = nil,
        flowSlug: String? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        _ = userId
        _store = StateObject(wrappedValue: ContactStore(flowSlug: flowSlug))
        self.onSubmitted = onSubmitted
    }

    private var accent: Color {
        store.form?.config.hero?.accentColor.flatMap(Color.init(amHex:)) ?? .accentColor
    }

    public var body: some View {
        ScrollView {
            if store.submitted {
                ContactSuccessCard(config: store.form?.config.success, accent: accent)
                    .padding(20)
            } else if let form = store.form {
                formBody(form.config).padding(20)
            } else if let err = store.loadError {
                VStack { ContactErrorState(message: err) { Task { await store.load() } } }
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                VStack { ProgressView() }.frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .task { if store.form == nil { await store.load() } }
        .onChange(of: store.submitted) { done in if done { onSubmitted?() } }
    }

    @ViewBuilder private func formBody(_ cfg: ContactConfig) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(cfg.intro.title).font(.title2).bold()
                if !cfg.intro.subtitle.isEmpty {
                    Text(cfg.intro.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if cfg.nameField?.enabled == true {
                ContactCard {
                    LabeledField(label: "Name") {
                        TextField(cfg.nameField?.placeholder ?? "Your name", text: $store.name)
                    }
                }
            }
            if cfg.emailField?.enabled == true {
                ContactCard {
                    LabeledField(label: "Email") {
                        ContactEmailField(
                            text: $store.email,
                            placeholder: cfg.emailField?.placeholder ?? "you@example.com"
                        )
                    }
                }
            }
            if cfg.messageField?.enabled == true {
                ContactCard {
                    ContactMessageEditor(
                        text: $store.message,
                        placeholder: cfg.messageField?.placeholder ?? "Your message"
                    )
                }
            }

            ForEach(cfg.fields ?? []) { field in
                ContactCard { ContactCustomFieldRow(field: field, value: bindingFor(field.id)) }
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

    private func bindingFor(_ id: String) -> Binding<String> {
        Binding(
            get: { store.fieldValues[id] ?? "" },
            set: { store.fieldValues[id] = $0 }
        )
    }
}

// MARK: - Pieces (file-private)

@available(iOS 16.0, macOS 13.0, *)
private struct ContactCard<Content: View>: View {
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
private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium))
            content
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct ContactEmailField: View {
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
private struct ContactMessageEditor: View {
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
private struct ContactCustomFieldRow: View {
    let field: ContactConfig.Field
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
private struct ContactSuccessCard: View {
    let config: ContactConfig.Success?
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
private struct ContactErrorState: View {
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
