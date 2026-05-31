import Foundation
#if canImport(UIKit)
import UIKit
#endif

// Web-to-app onboarding funnel support.
//
// Two integration paths:
//
//  1. DEFERRED (the headline case): the user completes a web funnel from your
//     ad / link-in-bio BEFORE installing. On first launch call
//     ``RetentionFlow/fetchOnboardingResult(userId:anonymousId:)`` — it reads
//     the claim token the funnel left on the clipboard and returns the
//     captured answers + email.
//
//  2. IN-APP: an already-installed user runs the funnel inside a Safari sheet
//     via ``RetentionFlow/startOnboardingFlow(...)``. The funnel returns a
//     deep link on completion; the SDK claims it and calls your `onComplete`.

extension RetentionFlow {
    /// Prefix the AppMate funnel writes ahead of the claim token so the SDK
    /// can recognize one on the clipboard without redeeming arbitrary text.
    private static let onboardingClaimPrefix = "amob_"

    /// Redeem a claim token for the answers + email captured by a web funnel.
    /// Most apps use ``fetchOnboardingResult(userId:anonymousId:)`` instead;
    /// call this directly only if you obtained the token yourself (e.g. from a
    /// custom deep link).
    public static func claimOnboarding(
        claimToken: String,
        userId: String? = nil,
        anonymousId: String? = nil
    ) async -> OnboardingResult? {
        guard let config = config else {
            assertionFailure(ConfigurationError.notConfigured.localizedDescription)
            return nil
        }
        let client = SessionClient(config: config)
        return try? await client.claimOnboarding(
            claimToken: claimToken,
            userId: userId,
            anonymousId: anonymousId
        )
    }

    #if canImport(UIKit)
    /// Deferred web→app attribution. Call once on first launch (or after
    /// sign-up, once you have a stable `userId`). If the user completed your
    /// web onboarding funnel before installing, the funnel left a claim token
    /// on the clipboard; this reads it, recovers the captured answers + email,
    /// clears the token from the clipboard, and returns the result.
    ///
    /// Returns `nil` when there's no AppMate claim token on the clipboard
    /// (the common case for organic installs) or the claim failed.
    ///
    /// > Note: reading the clipboard shows the standard iOS paste banner. Call
    /// > this at a natural "we're setting things up" moment, not silently at
    /// > the very first frame, so the banner reads as expected.
    @MainActor
    public static func fetchOnboardingResult(
        userId: String? = nil,
        anonymousId: String? = nil
    ) async -> OnboardingResult? {
        guard config != nil else {
            assertionFailure(ConfigurationError.notConfigured.localizedDescription)
            return nil
        }
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings,
              let text = pasteboard.string?.trimmingCharacters(
                in: .whitespacesAndNewlines
              ),
              text.hasPrefix(onboardingClaimPrefix)
        else { return nil }

        let result = await claimOnboarding(
            claimToken: text,
            userId: userId,
            anonymousId: anonymousId
        )
        // Clear our token so a later launch doesn't re-claim it. Only clear
        // when it's still our token (the user may have copied something else
        // in the meantime).
        if result != nil, pasteboard.string == text {
            pasteboard.string = ""
        }
        return result
    }

    /// Present the onboarding funnel in a Safari sheet for an already-installed
    /// user (e.g. a "redo setup" button). The funnel returns a deep link on
    /// completion; the SDK dismisses the sheet, claims the result, and invokes
    /// `onComplete` on the main actor. `onComplete` receives `nil` if the user
    /// dismissed the sheet manually or the claim failed.
    @MainActor
    public static func startOnboardingFlow(
        userId: String? = nil,
        anonymousId: String? = nil,
        attributes: [String: Any]? = nil,
        from presenter: UIViewController? = nil,
        onComplete: ((OnboardingResult?) -> Void)? = nil
    ) {
        guard let config = config else {
            assertionFailure(ConfigurationError.notConfigured.localizedDescription)
            return
        }

        let locale = Locale.current.identifier
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        Task { @MainActor in
            do {
                let client = SessionClient(config: config)
                let resp = try await client.startOnboardingFlow(
                    userId: userId,
                    anonymousId: anonymousId,
                    locale: locale,
                    appVersion: appVersion,
                    attributes: attributes
                )

                // Append our scheme so the funnel emits the return deep link.
                guard var comps = URLComponents(string: resp.flowUrl) else {
                    onComplete?(nil)
                    return
                }
                comps.queryItems = (comps.queryItems ?? []) + [
                    URLQueryItem(name: "scheme", value: config.urlScheme)
                ]
                guard let url = comps.url else {
                    onComplete?(nil)
                    return
                }

                SafariPresenter.shared.present(
                    url: url,
                    from: presenter,
                    urlScheme: config.urlScheme,
                    onAction: { link in
                        guard case .onboardingComplete(let claimToken) =
                            link.action, let claimToken
                        else {
                            onComplete?(nil)
                            return
                        }
                        Task { @MainActor in
                            let result = await claimOnboarding(
                                claimToken: claimToken,
                                userId: userId,
                                anonymousId: anonymousId
                            )
                            onComplete?(result)
                        }
                    }
                )
            } catch {
                onComplete?(nil)
            }
        }
    }
    #endif
}
