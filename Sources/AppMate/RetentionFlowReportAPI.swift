import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Native report flow — typed config + submit, so clients can render the report
// form natively (see ReportView / RetentionFlow.presentReport) instead of the
// hosted web page. The web flow remains an option; this is additive.
//
// Report = pick a category (required, from the configured list) + write a
// message + optionally leave an email. Config-driven: only the categories and
// fields the owner configured are shown.
// ─────────────────────────────────────────────────────────────────────────────

public struct ReportConfig: Decodable, Sendable {
    public struct Intro: Decodable, Sendable {
        public let title: String
        public let subtitle: String
        public let messagePlaceholder: String
        public let submitLabel: String
        public let legal: String?
    }
    public struct Category: Decodable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let emoji: String?
        public let hint: String?
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
    public let categories: [Category]
    public let emailField: EmailField?
    public let success: Success
    public let colorScheme: String?
    public let hero: Hero?
}

/// Config + brand for rendering a native report form. Reuses ``FeedbackBrand``
/// (just the app's name/logo/website — same shape for every flow).
public struct ReportForm: Sendable {
    public let flowSlug: String
    public let app: FeedbackBrand
    public let config: ReportConfig
}

public enum ReportError: Error, LocalizedError {
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
            return "This report flow isn't published yet."
        case .http(let status, let body):
            return "Report request failed (\(status)): \(body ?? "no body")"
        case .transport(let err):
            return "Network error: \(err.localizedDescription)"
        case .decode(let err):
            return "Couldn't read the report config: \(err.localizedDescription)"
        }
    }
}

extension RetentionFlow {

    private struct ReportConfigEnvelope: Decodable {
        let flowSlug: String
        let app: FeedbackBrand
        let config: ReportConfig
    }

    /// Fetch the published report config + brand so you can render the form
    /// natively. `flowSlug` targets a non-primary report flow (omit for the
    /// primary). Throws `ReportError.notOpen` if it isn't published.
    public static func reportForm(flowSlug: String? = nil) async throws -> ReportForm {
        guard let config = config else { throw ReportError.notConfigured }
        var comps = URLComponents(
            url: config.baseURL.appendingPathComponent("api/public/report"),
            resolvingAgainstBaseURL: false,
        )
        var items = [URLQueryItem(name: "appSlug", value: config.appSlug)]
        if let flowSlug, !flowSlug.isEmpty {
            items.append(URLQueryItem(name: "flowSlug", value: flowSlug))
        }
        comps?.queryItems = items
        guard let url = comps?.url else { throw ReportError.notOpen }

        var req = URLRequest(url: url)
        req.timeoutInterval = config.requestTimeout
        req.addValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ReportError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 404 { throw ReportError.notOpen }
        guard (200..<300).contains(status) else {
            throw ReportError.http(
                status: status, body: String(data: data, encoding: .utf8))
        }
        do {
            let env = try JSONDecoder().decode(ReportConfigEnvelope.self, from: data)
            return ReportForm(flowSlug: env.flowSlug, app: env.app, config: env.config)
        } catch {
            throw ReportError.decode(error)
        }
    }

    private struct SubmitReportBody: Encodable {
        let appSlug: String
        let flowSlug: String?
        let category: String
        let message: String
        let email: String?
        let source: String
    }

    /// Submit a report. `category` is the chosen category id (required); `email`
    /// is only accepted when the flow enables it. Throws on validation/network
    /// failure.
    public static func submitReport(
        category: String,
        message: String,
        email: String? = nil,
        flowSlug: String? = nil
    ) async throws {
        guard let config = config else { throw ReportError.notConfigured }
        let endpoint = config.baseURL.appendingPathComponent("api/public/report")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = config.requestTimeout
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(
            SubmitReportBody(
                appSlug: config.appSlug,
                flowSlug: flowSlug,
                category: category,
                message: message,
                email: email?.isEmpty == false ? email : nil,
                source: "sdk",
            ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ReportError.transport(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw ReportError.http(
                status: status, body: String(data: data, encoding: .utf8))
        }
    }
}
