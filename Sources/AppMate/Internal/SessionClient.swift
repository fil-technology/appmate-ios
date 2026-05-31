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

    // MARK: Onboarding (web-to-app funnel)

    /// Start an onboarding-funnel session. Same response shape as the cancel
    /// flow — `flowUrl` is the hosted funnel to present in a Safari sheet.
    func startOnboardingFlow(
        userId: String?,
        anonymousId: String?,
        locale: String?,
        appVersion: String?,
        attributes: [String: Any]?
    ) async throws -> StartResponse {
        let endpoint = config.baseURL.appendingPathComponent(
            "api/public/onboarding/sessions"
        )

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

    private struct ClaimRequest: Encodable {
        let appSlug: String
        let claimToken: String
        let userId: String?
        let anonymousId: String?
    }

    private struct ClaimResponse: Decodable {
        let answers: [String: OnboardingAnswer]?
        let email: String?
        let completedAt: String?
        let claimedAt: String?
        let alreadyClaimed: Bool?
    }

    /// Redeem a claim token for the captured onboarding answers + email.
    func claimOnboarding(
        claimToken: String,
        userId: String?,
        anonymousId: String?
    ) async throws -> OnboardingResult {
        let endpoint = config.baseURL.appendingPathComponent(
            "api/public/onboarding/claim"
        )
        let body = ClaimRequest(
            appSlug: config.appSlug,
            claimToken: claimToken,
            userId: userId,
            anonymousId: anonymousId
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
            let decoded = try JSONDecoder().decode(ClaimResponse.self, from: data)
            return OnboardingResult(
                answers: decoded.answers ?? [:],
                email: decoded.email,
                alreadyClaimed: decoded.alreadyClaimed ?? false
            )
        } catch {
            throw ClientError.decode(error)
        }
    }

    // MARK: Referral

    /// POST a JSON body to a public path and decode the response. Shared by
    /// the referral calls.
    private func postJSON<Body: Encodable, Out: Decodable>(
        path: String,
        body: Body,
        as: Out.Type
    ) async throws -> Out {
        let endpoint = config.baseURL.appendingPathComponent(path)
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
            return try JSONDecoder().decode(Out.self, from: data)
        } catch {
            throw ClientError.decode(error)
        }
    }

    struct ReferralCodeRequest: Encodable {
        let appSlug: String
        let userId: String
    }
    struct ReferralCodeResponse: Decodable {
        let code: String
        let shareUrl: String
        let shareMessage: String?
        let referrerWeeks: Int?
        let referrerLabel: String?
    }

    func referralCode(userId: String) async throws -> ReferralCodeResponse {
        try await postJSON(
            path: "api/public/referral/code",
            body: ReferralCodeRequest(appSlug: config.appSlug, userId: userId),
            as: ReferralCodeResponse.self
        )
    }

    struct ReferralAttributeRequest: Encodable {
        let appSlug: String
        let claimToken: String
        let userId: String?
        let anonymousId: String?
    }
    struct RewardPayload: Decodable {
        let weeks: Int
        let label: String?
    }
    struct ReferralAttributeResponse: Decodable {
        let attributed: Bool?
        let alreadyAttributed: Bool?
        let refereeReward: RewardPayload?
    }

    func attributeReferral(
        claimToken: String,
        userId: String?,
        anonymousId: String?
    ) async throws -> ReferralAttributeResponse {
        try await postJSON(
            path: "api/public/referral/attribute",
            body: ReferralAttributeRequest(
                appSlug: config.appSlug,
                claimToken: claimToken,
                userId: userId,
                anonymousId: anonymousId
            ),
            as: ReferralAttributeResponse.self
        )
    }

    struct ReferralRewardsRequest: Encodable {
        let appSlug: String
        let userId: String
    }
    struct ReferralRewardsResponse: Decodable {
        let weeksOwed: Int
        let newReferrals: Int
        let referrerWeeksEach: Int?
        let totalRewarded: Int?
        let cappedOut: Int?
    }

    func referralRewards(userId: String) async throws -> ReferralRewardsResponse {
        try await postJSON(
            path: "api/public/referral/rewards",
            body: ReferralRewardsRequest(appSlug: config.appSlug, userId: userId),
            as: ReferralRewardsResponse.self
        )
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
