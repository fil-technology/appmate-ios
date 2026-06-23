import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Native contact flow — typed config + submit, so clients can render the
// contact form natively (see ContactView / RetentionFlow.presentContact)
// instead of the hosted web page. The web flow remains an option; additive.
//
// Contact = name / email / message, each independently opt-in (+ optional
// required) in the dashboard, plus any custom fields. Config-driven.
// ─────────────────────────────────────────────────────────────────────────────

public struct ContactConfig: Decodable, Sendable {
    public struct Intro: Decodable, Sendable {
        public let title: String
        public let subtitle: String
        public let submitLabel: String
        public let legal: String?
    }
    public struct FieldToggle: Decodable, Sendable {
        public let enabled: Bool
        public let placeholder: String?
        public let required: Bool?
    }
    public struct Field: Decodable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let type: String
        public let placeholder: String?
        public let options: [String]?
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
    public let nameField: FieldToggle?
    public let emailField: FieldToggle?
    public let messageField: FieldToggle?
    public let fields: [Field]?
    public let success: Success
    public let colorScheme: String?
    public let hero: Hero?
}

/// Config + brand for rendering a native contact form.
public struct ContactForm: Sendable {
    public let flowSlug: String
    public let app: FeedbackBrand
    public let config: ContactConfig
}

public enum ContactError: Error, LocalizedError {
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
            return "This contact flow isn't published yet."
        case .http(let status, let body):
            return "Contact request failed (\(status)): \(body ?? "no body")"
        case .transport(let err):
            return "Network error: \(err.localizedDescription)"
        case .decode(let err):
            return "Couldn't read the contact config: \(err.localizedDescription)"
        }
    }
}

extension RetentionFlow {

    private struct ContactConfigEnvelope: Decodable {
        let flowSlug: String
        let app: FeedbackBrand
        let config: ContactConfig
    }

    /// Fetch the published contact config + brand so you can render the form
    /// natively. `flowSlug` targets a non-primary contact flow (omit for the
    /// primary). Throws `ContactError.notOpen` if it isn't published.
    public static func contactForm(flowSlug: String? = nil) async throws -> ContactForm {
        guard let config = config else { throw ContactError.notConfigured }
        var comps = URLComponents(
            url: config.baseURL.appendingPathComponent("api/public/contact"),
            resolvingAgainstBaseURL: false,
        )
        var items = [URLQueryItem(name: "appSlug", value: config.appSlug)]
        if let flowSlug, !flowSlug.isEmpty {
            items.append(URLQueryItem(name: "flowSlug", value: flowSlug))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { throw ContactError.notOpen }

        var req = URLRequest(url: url)
        req.timeoutInterval = config.requestTimeout
        req.addValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ContactError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 404 { throw ContactError.notOpen }
        guard (200..<300).contains(status) else {
            throw ContactError.http(
                status: status, body: String(data: data, encoding: .utf8))
        }
        do {
            let env = try JSONDecoder().decode(ContactConfigEnvelope.self, from: data)
            return ContactForm(flowSlug: env.flowSlug, app: env.app, config: env.config)
        } catch {
            throw ContactError.decode(error)
        }
    }

    private struct SubmitContactBody: Encodable {
        let appSlug: String
        let flowSlug: String?
        let name: String?
        let email: String?
        let message: String?
        let attributes: [String: String]?
        let source: String
    }

    /// Submit a contact form. Each of `name` / `email` / `message` is only
    /// accepted when the flow enables it; `fields` carries custom-field answers
    /// keyed by field id. Throws on validation/network failure.
    public static func submitContact(
        name: String? = nil,
        email: String? = nil,
        message: String? = nil,
        fields: [String: String]? = nil,
        flowSlug: String? = nil
    ) async throws {
        guard let config = config else { throw ContactError.notConfigured }
        let endpoint = config.baseURL.appendingPathComponent("api/public/contact")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = config.requestTimeout
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(
            SubmitContactBody(
                appSlug: config.appSlug,
                flowSlug: flowSlug,
                name: name?.isEmpty == false ? name : nil,
                email: email?.isEmpty == false ? email : nil,
                message: message?.isEmpty == false ? message : nil,
                attributes: (fields?.isEmpty == false) ? fields : nil,
                source: "sdk",
            ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ContactError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw ContactError.http(
                status: status, body: String(data: data, encoding: .utf8))
        }
    }
}
