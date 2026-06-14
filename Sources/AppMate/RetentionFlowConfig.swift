import Foundation

/// Static configuration the host app provides once at launch via
/// ``RetentionFlow/configure(_:)``.
public struct RetentionFlowConfig: Sendable {
    /// The app's slug in your AppMate dashboard (e.g. `"my-ios-app"`).
    /// The hosted flow URL becomes `{baseURL}/{appSlug}`.
    public let appSlug: String

    /// Root of your AppMate deployment's cancel surface, e.g.
    /// `https://cancel.appmate.cloud` or `https://flow.your-domain.com`.
    /// The SDK appends `/api/public/sessions` for session creation and
    /// `/{appSlug}` for the hosted flow itself.
    public let baseURL: URL

    /// Your app's custom URL scheme as registered in Info.plist
    /// (e.g. `"myapp"`). Used to validate that an inbound URL came from
    /// AppMate before parsing it.
    public let urlScheme: String

    /// Root of the host that serves your *web* flow pages — contact, report,
    /// feedback, the wishlist board, etc. (e.g. `https://appmate.cloud`).
    ///
    /// Only the shake "feedback menu" needs this, because those flows live on
    /// the apex host rather than the cancel subdomain. Leave it `nil` and the
    /// SDK derives it from ``baseURL`` by dropping a leading `cancel.` /
    /// `flow.` / `signup.` label (so `https://cancel.appmate.cloud` →
    /// `https://appmate.cloud`). Set it explicitly if you use custom domains.
    public let webBaseURL: URL?

    /// Optional request timeout for the session bootstrap call.
    /// Defaults to 10 seconds.
    public let requestTimeout: TimeInterval

    public init(
        appSlug: String,
        baseURL: URL,
        urlScheme: String,
        webBaseURL: URL? = nil,
        requestTimeout: TimeInterval = 10
    ) {
        self.appSlug = appSlug
        self.baseURL = baseURL
        self.urlScheme = urlScheme
        self.webBaseURL = webBaseURL
        self.requestTimeout = requestTimeout
    }
}
