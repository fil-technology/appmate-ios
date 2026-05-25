import Foundation

/// Talks to `POST {baseURL}/api/public/sessions`. Internal — host apps don't
/// see this; they call ``RetentionFlow/startCancelFlow(...)`` instead.
struct SessionClient {
    struct StartRequest: Encodable {
        let appSlug: String
        let userId: String?
        let anonymousId: String?
        let platform: String
        let locale: String?
        let appVersion: String?
        let attributes: [String: AnyEncodable]?
    }

    struct StartResponse: Decodable {
        let sessionId: String
        let token: String
        let flowUrl: String
    }

    enum ClientError: Error, LocalizedError {
        case invalidURL
        case http(status: Int, body: String?)
        case transport(Error)
        case decode(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "AppMate baseURL is not a valid HTTP URL."
            case .http(let status, let body):
                "AppMate session start failed (\(status)): \(body ?? "no body")"
            case .transport(let err): "AppMate network error: \(err.localizedDescription)"
            case .decode(let err): "AppMate response decode error: \(err.localizedDescription)"
            }
        }
    }

    let config: RetentionFlowConfig
    let session: URLSession

    init(config: RetentionFlowConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func startCancelFlow(
        userId: String?,
        anonymousId: String?,
        locale: String?,
        appVersion: String?,
        attributes: [String: Any]?
    ) async throws -> StartResponse {
        let endpoint = config.baseURL.appendingPathComponent("api/public/sessions")

        let body = StartRequest(
            appSlug: config.appSlug,
            userId: userId,
            anonymousId: anonymousId,
            platform: "ios",
            locale: locale,
            appVersion: appVersion,
            attributes: attributes?.mapValues(AnyEncodable.init)
        )

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = config.requestTimeout
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ClientError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.http(status: -1, body: nil)
        }
        guard (200...299).contains(http.statusCode) else {
            throw ClientError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }

        do {
            return try JSONDecoder().decode(StartResponse.self, from: data)
        } catch {
            throw ClientError.decode(error)
        }
    }
}

/// Type-erasing wrapper so we can encode `[String: Any]` attributes through
/// JSONEncoder. Supports the JSON-compatible scalar types; everything else is
/// silently dropped as `null`.
struct AnyEncodable: Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let s as String: try container.encode(s)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let b as Bool: try container.encode(b)
        case let arr as [Any]:
            try container.encode(arr.map(AnyEncodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyEncodable.init))
        case Optional<Any>.none:
            try container.encodeNil()
        default:
            // Best-effort string fallback so debugging is possible.
            try container.encode(String(describing: value))
        }
    }
}
