import Foundation
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// StoreKit 2 helper for opening the system "Manage Subscriptions" sheet.
/// Falls back to opening the App Store subscriptions URL in Safari if the
/// in-app sheet can't be presented (e.g. running on Simulator without a
/// signed-in App Store account).
public enum RetentionFlowSubscriptionManager {
    public static let appleSubscriptionsURL = URL(
        string: "https://apps.apple.com/account/subscriptions"
    )!

    /// Present Apple's native manage-subscriptions sheet.
    ///
    /// On real devices this opens the in-app StoreKit sheet. On Simulator or
    /// when StoreKit throws (most commonly: no signed-in App Store account)
    /// this falls back to opening the App Store URL in Safari.
    ///
    /// Always returns; never throws.
    @MainActor
    public static func presentManageSubscriptions(
        from scene: UIWindowScene? = nil
    ) async {
        #if canImport(StoreKit) && canImport(UIKit)
        let targetScene = scene ?? activeWindowScene()
        if let targetScene {
            do {
                try await AppStore.showManageSubscriptions(in: targetScene)
                return
            } catch {
                // Fall through to URL fallback.
            }
        }
        await openFallbackURL()
        #else
        await openFallbackURL()
        #endif
    }

    @MainActor
    private static func openFallbackURL() async {
        #if canImport(UIKit)
        _ = await UIApplication.shared.open(appleSubscriptionsURL)
        #endif
    }

    #if canImport(UIKit)
    @MainActor
    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    }
    #endif
}
