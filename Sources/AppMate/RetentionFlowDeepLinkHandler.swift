import Foundation

/// Parses incoming deep-link URLs from the AppMate hosted flow into typed
/// ``RetentionFlowDeepLink`` values.
///
/// Expected URL shape:
///
///     {scheme}://retention-flow/action
///       ?type=...
///       &session_id=...
///       [&feature_id=...]
///       [&url=...]
public enum RetentionFlowDeepLinkHandler {
    /// Parse a URL into a typed action + session id.
    ///
    /// Returns `nil` if the URL doesn't match the contract — e.g. wrong
    /// scheme, missing host/path, or unknown `type`. Callers should pass
    /// every inbound URL through this and ignore `nil` results (they're
    /// not AppMate URLs).
    public static func parse(
        _ url: URL,
        expectedScheme: String? = nil
    ) -> RetentionFlowDeepLink? {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else { return nil }

        // Scheme check — if the host app told us its scheme, enforce it.
        if let expectedScheme {
            guard components.scheme?.lowercased() == expectedScheme.lowercased()
            else { return nil }
        }

        // Path-based discriminator. We deliberately require both the host
        // "retention-flow" and the path "/action" so a misconfigured host
        // app can't accidentally route arbitrary deep links to us.
        guard components.host == "retention-flow",
              components.path == "/action"
        else { return nil }

        let items = components.queryItems ?? []
        let type = items.first(where: { $0.name == "type" })?.value
        let sessionId = items.first(where: { $0.name == "session_id" })?.value

        guard let type else { return nil }

        let action: RetentionFlowAction
        switch type {
        case "return_to_app":
            action = .returnToApp
        case "open_premium":
            action = .openPremium
        case "open_support":
            action = .openSupport
        case "open_feature":
            guard let featureId = items.first(where: { $0.name == "feature_id" })?.value,
                  !featureId.isEmpty
            else { return nil }
            action = .openFeature(id: featureId)
        case "manage_subscription":
            action = .manageSubscription
        case "external_url":
            guard let raw = items.first(where: { $0.name == "url" })?.value,
                  let url = URL(string: raw)
            else { return nil }
            action = .externalURL(url)
        case "none":
            action = .none
        default:
            // Unknown action type — newer server config than this SDK
            // version supports. Surface as `.none` rather than nil so the
            // host app at least knows an AppMate URL was received.
            action = .none
        }

        return RetentionFlowDeepLink(
            action: action,
            sessionId: sessionId,
            rawQueryItems: items
        )
    }
}
