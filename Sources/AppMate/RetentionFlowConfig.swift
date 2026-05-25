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

    /// Optional request timeout for the session bootstrap call.
    /// Defaults to 10 seconds.
    public let requestTimeout: TimeInterval

    public init(
        appSlug: String,
        baseURL: URL,
        urlScheme: String,
        requestTimeout: TimeInterval = 10
    ) {
        self.appSlug = appSlug
        self.baseURL = baseURL
        self.urlScheme = urlScheme
        self.requestTimeout = requestTimeout
    }
}
