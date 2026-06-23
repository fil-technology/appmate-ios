import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Native feedback flow — typed config + submit, so clients can render the
// feedback form with NATIVE SwiftUI (see FeedbackView / RetentionFlow
// .presentFeedback) instead of the hosted web page. Both are options: the web
// flow (presentURL / the hosted page) still works; this adds a native path.
//
// The form is config-driven: it mirrors exactly what the owner enabled in the
// dashboard (star rating, reply-email field, custom fields) — nothing more.
// ─────────────────────────────────────────────────────────────────────────────

/// The published feedback flow config, as the dashboard configured it.
public struct FeedbackConfig: Decodable, Sendable {
    public struct Intro: Decodable, Sendable {
        public let title: String
        public let subtitle: String
        public let messagePlaceholder: String
        public let submitLabel: String
        public let legal: String?
    }
    public struct Rating: Decodable, Sendable {
        public let enabled: Bool
        public let prompt: String?
        public let required: Bool?
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
    /// Owner-defined extra field. `type` is "text" | "select" | "boolean".
    public struct Field: Decodable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let type: String
        public let placeholder: String?
        public let options: [String]?
        public let required: Bool?
    }
    public struct Hero: Decodable, Sendable {
        public let accentColor: String?
    }

    public let intro: Intro
    public let rating: Rating?
    public let emailField: EmailField?
    public let success: Success
    public let fields: [Field]?
    public let colorScheme: String?
    public let hero: Hero?
}

/// App brand returned alongside the config (for the form header).
public struct FeedbackBrand: Decodable, Sendable {
    public let name: String
    public let logoUrl: String?
    public let websiteUrl: String?
}

/// Config + brand for rendering a native feedback form.
public struct FeedbackForm: Sendable {
    public let flowSlug: String
    public let app: FeedbackBrand
    public let config: FeedbackConfig
}

public enum FeedbackError: Error, LocalizedError {
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
            return "This feedback flow isn't published yet."
        case .http(let status, let body):
            return "Feedback request failed (\(status)): \(body ?? "no body")"
        case .transport(let err):
            return "Network error: \(err.localizedDescription)"
        case .decode(let err):
            return "Couldn't read the feedback config: \(err.localizedDescription)"
        }
    }
}

extension RetentionFlow {

    private struct FeedbackConfigEnvelope: Decodable {
        let flowSlug: String
        let app: FeedbackBrand
        let config: FeedbackConfig
    }

    /// Fetch the published feedback config + brand so you can render the form
    /// natively. `flowSlug` targets a non-primary feedback flow (omit for the
    /// primary). Throws `FeedbackError.notOpen` if it isn't published.
    public static func feedbackForm(flowSlug: String? = nil) async throws -> FeedbackForm {
        guard let config = config else { throw FeedbackError.notConfigured }
        var comps = URLComponents(
            url: config.baseURL.appendingPathComponent("api/public/feedback"),
            resolvingAgainstBaseURL: false,
        )
        var items = [URLQueryItem(name: "appSlug", value: config.appSlug)]
        if let flowSlug, !flowSlug.isEmpty {
            items.append(URLQueryItem(name: "flowSlug", value: flowSlug))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { throw FeedbackError.notOpen }

        var req = URLRequest(url: url)
        req.timeoutInterval = config.requestTimeout
        req.addValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw FeedbackError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 404 { throw FeedbackError.notOpen }
        guard (200..<300).contains(status) else {
            throw FeedbackError.http(
                status: status, body: String(data: data, encoding: .utf8))
        }
        do {
            let env = try JSONDecoder().decode(FeedbackConfigEnvelope.self, from: data)
            return FeedbackForm(flowSlug: env.flowSlug, app: env.app, config: env.config)
        } catch {
            throw FeedbackError.decode(error)
        }
    }

    private struct SubmitFeedbackBody: Encodable {
        let appSlug: String
        let flowSlug: String?
        let message: String
        let rating: Int?
        let email: String?
        let attributes: [String: String]?
        let source: String
    }

    /// Submit a feedback message. `rating` (1–5) and `email` are only accepted
    /// when the flow enables them; `fields` carries custom-field answers keyed
    /// by field id. Throws on validation/network failure.
    public static func submitFeedback(
        message: String,
        rating: Int? = nil,
        email: String? = nil,
        fields: [String: String]? = nil,
        flowSlug: String? = nil
    ) async throws {
        guard let config = config else { throw FeedbackError.notConfigured }
        let endpoint = config.baseURL.appendingPathComponent("api/public/feedback")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = config.requestTimeout
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(
            SubmitFeedbackBody(
                appSlug: config.appSlug,
                flowSlug: flowSlug,
                message: message,
                rating: rating,
                email: email?.isEmpty == false ? email : nil,
                attributes: (fields?.isEmpty == false) ? fields : nil,
                source: "sdk",
            ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw FeedbackError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw FeedbackError.http(
                status: status, body: String(data: data, encoding: .utf8))
        }
    }
}
