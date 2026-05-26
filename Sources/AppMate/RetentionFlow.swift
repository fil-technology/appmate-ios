import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Top-level entry point for the AppMate iOS SDK.
///
/// Typical integration:
///
/// 1. Call ``configure(_:)`` once at launch (`@main App` init or
///    `application(_:didFinishLaunchingWithOptions:)`).
/// 2. When the user taps "Cancel Subscription" in your app, call
///    ``startCancelFlow(userId:attributes:from:onAction:)``.
/// 3. Inside your `onAction` callback (or via your app's `.onOpenURL` /
///    `application(_:open:options:)`) switch on the returned action and
///    navigate accordingly.
public enum RetentionFlow {

    // MARK: Configuration

    nonisolated(unsafe) private static var _config: RetentionFlowConfig?

    /// Set once at launch. Subsequent calls overwrite the previous config.
    public static func configure(_ config: RetentionFlowConfig) {
        _config = config
    }

    /// Returns the active config or `nil` if ``configure(_:)`` was never
    /// called. Throws-on-use happens via ``ConfigurationError`` below.
    public static var config: RetentionFlowConfig? { _config }

    public enum ConfigurationError: Error, LocalizedError {
        case notConfigured
        public var errorDescription: String? {
            "RetentionFlow.configure(_:) must be called before any other SDK method."
        }
    }

    // MARK: Starting the cancel flow

    /// Starts a cancel flow session and presents the hosted UI in an
    /// `SFSafariViewController`. The `onAction` callback fires once the user
    /// completes the flow with one of the supported actions; the SDK
    /// auto-dismisses the Safari view at that point.
    ///
    /// - Parameters:
    ///   - userId: Stable identifier for the user (optional). If omitted,
    ///     supply `anonymousId` to keep analytics joinable.
    ///   - anonymousId: Pre-login or anonymous identifier (optional).
    ///   - attributes: Arbitrary JSON-compatible context surfaced in the
    ///     dashboard session detail (e.g. `["plan": "monthly"]`).
    ///   - from: View controller to present from. If `nil` the SDK locates
    ///     the active window's topmost view controller.
    ///   - onAction: Called on the main actor when the user picks a final
    ///     action. Use this to navigate inside your app. May not fire if
    ///     the user dismisses the Safari sheet manually.
    #if canImport(UIKit)
    @MainActor
    public static func startCancelFlow(
        userId: String? = nil,
        anonymousId: String? = nil,
        attributes: [String: Any]? = nil,
        from presenter: UIViewController? = nil,
        onAction: ((RetentionFlowDeepLink) -> Void)? = nil
    ) {
        guard let config = _config else {
            assertionFailure(ConfigurationError.notConfigured.localizedDescription)
            return
        }

        let locale = Locale.current.identifier
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        Task { @MainActor in
            do {
                let client = SessionClient(config: config)
                let resp = try await client.startCancelFlow(
                    userId: userId,
                    anonymousId: anonymousId,
                    locale: locale,
                    appVersion: appVersion,
                    attributes: attributes
                )
                guard let url = URL(string: resp.flowUrl) else { return }
                SafariPresenter.shared.present(
                    url: url,
                    from: presenter,
                    urlScheme: config.urlScheme,
                    onAction: onAction
                )
            } catch {
                // Soft failure: if we couldn't reach the AppMate server we
                // never want to block the user from cancelling. Synthesize a
                // .manageSubscription action so the host app can route them
                // straight to the App Store.
                onAction?(
                    RetentionFlowDeepLink(
                        action: .manageSubscription,
                        sessionId: nil,
                        rawQueryItems: []
                    )
                )
            }
        }
    }
    #endif

    // MARK: Deep link handling

    /// Parse an inbound URL — typically from SwiftUI's `.onOpenURL { url in }`
    /// or UIKit's `application(_:open:options:)` — into a typed AppMate
    /// action. Returns `nil` if the URL isn't an AppMate deep link.
    public static func deepLink(from url: URL) -> RetentionFlowDeepLink? {
        RetentionFlowDeepLinkHandler.parse(
            url,
            expectedScheme: _config?.urlScheme
        )
    }

    /// Convenience: parse the URL and invoke the callback if it matches.
    /// Returns `true` if the URL was an AppMate deep link, `false` otherwise.
    @discardableResult
    public static func handleDeepLink(
        _ url: URL,
        onAction: (RetentionFlowDeepLink) -> Void
    ) -> Bool {
        guard let link = deepLink(from: url) else { return false }
        onAction(link)
        return true
    }

    // MARK: Apple's manage-subscriptions sheet

    #if canImport(UIKit)
    /// See ``RetentionFlowSubscriptionManager/presentManageSubscriptions(from:)``.
    @MainActor
    public static func presentManageSubscriptions(
        from scene: UIWindowScene? = nil
    ) async {
        await RetentionFlowSubscriptionManager.presentManageSubscriptions(
            from: scene
        )
    }
    #endif

    // MARK: Generic Safari-sheet presentation
    //
    // The cancel-flow path is the headline use case but the same plumbing —
    // open an `SFSafariViewController` and listen for deep-link redirects
    // that match the configured URL scheme — is useful for any
    // AppMate-hosted surface: a preview link, a marketing landing the host
    // app wants to open in-app, a waitlist signup, etc.
    //
    // `dismissFlow()` lets the host app close whatever Safari sheet AppMate
    // currently has up — useful when app state changes (e.g. the user
    // logged out elsewhere) and you don't want a stale cancel UI hanging
    // around. Safe to call when nothing is presented.

    #if canImport(UIKit)
    /// Open an arbitrary AppMate URL in an `SFSafariViewController`. The
    /// presenter watches the same redirect stream the cancel flow uses, so
    /// any AppMate deep link the web page navigates to (return-to-app,
    /// open-feature, etc.) fires `onAction` and the sheet is dismissed.
    ///
    /// - Parameters:
    ///   - url: The AppMate-hosted URL to present. Must be https.
    ///   - presenter: View controller to present from. Defaults to the
    ///     top-most foreground VC.
    ///   - onAction: Same shape as `startCancelFlow`'s callback.
    @MainActor
    public static func presentURL(
        _ url: URL,
        from presenter: UIViewController? = nil,
        onAction: ((RetentionFlowDeepLink) -> Void)? = nil
    ) {
        guard let config = _config else {
            assertionFailure(ConfigurationError.notConfigured.localizedDescription)
            return
        }
        SafariPresenter.shared.present(
            url: url,
            from: presenter,
            urlScheme: config.urlScheme,
            onAction: onAction
        )
    }

    /// Programmatically close the AppMate-presented Safari sheet, if any.
    /// No-op when nothing is presented. Useful for host-app state changes
    /// (sign-out, deep-link from elsewhere, etc.) where the cancel UI
    /// should disappear without waiting for the user to tap Done.
    @MainActor
    public static func dismissFlow() {
        SafariPresenter.shared.dismissIfPresentedPublic()
    }
    #endif
}
