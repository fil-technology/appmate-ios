import Foundation

/// Action returned to the host app when the user closes the AppMate
/// pre-cancel flow via a deep link.
///
/// The wire format (parsed from `myapp://retention-flow/action?type=...`) and
/// the supported set are defined in the AppMate service repo at
/// `docs/deep-link-contract.md` — keep these in sync if you change anything.
public enum RetentionFlowAction: Equatable, Sendable {
    /// User chose to return to the app. Navigate to your main / home screen.
    case returnToApp

    /// User chose to see your premium / paywall screen. `paywallId` is set
    /// when the dashboard targets a specific paywall variant (e.g.
    /// "cancel_save_monthly"); nil for the default screen.
    case openPremium(paywallId: String?)

    /// User wants to contact support. `topic` and `message` may be set if the
    /// dashboard pre-configured them (e.g. "technical_issue" topic for a bug
    /// report flow). Pre-fill your support sheet with them when available.
    case openSupport(topic: String?, message: String?)

    /// User chose to open a specific feature, tutorial, or onboarding flow.
    /// The `id` is whatever the dashboard sends — your app decides what to
    /// open for each id.
    case openFeature(id: String)

    /// User wants to claim a retention offer. The id is opaque to AppMate —
    /// your app maps it to a StoreKit promotional offer, RevenueCat offering,
    /// or any in-app paywall configuration.
    case openOffer(id: String)

    /// User chose to continue cancelling. Call
    /// ``RetentionFlow/presentManageSubscriptions(from:)`` (StoreKit 2) or
    /// open `https://apps.apple.com/account/subscriptions` as a fallback.
    case manageSubscription

    /// User chose an external link configured in the dashboard. Open with
    /// `UIApplication.shared.open(_:)` or your app's webview.
    case externalURL(URL)

    /// Reserved / no-op action.
    case none
}

/// Parsed-out shape that pairs the action with the session id and any
/// raw query items the host app might want.
public struct RetentionFlowDeepLink: Equatable, Sendable {
    public let action: RetentionFlowAction
    public let sessionId: String?
    public let rawQueryItems: [URLQueryItem]

    public init(
        action: RetentionFlowAction,
        sessionId: String?,
        rawQueryItems: [URLQueryItem]
    ) {
        self.action = action
        self.sessionId = sessionId
        self.rawQueryItems = rawQueryItems
    }
}
