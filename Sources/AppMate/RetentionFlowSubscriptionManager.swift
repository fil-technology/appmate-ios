import Foundation
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
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
    #if canImport(UIKit)
    @MainActor
    public static func presentManageSubscriptions(
        from scene: UIWindowScene? = nil
    ) async {
        #if canImport(StoreKit)
        let targetScene = scene ?? activeWindowScene()
        if let targetScene {
            do {
                try await AppStore.showManageSubscriptions(in: targetScene)
                return
            } catch {
                // Fall through to URL fallback.
            }
        }
        #endif
        await openFallbackURL()
    }
    #else
    /// (macOS / non-UIKit) Open the App Store subscriptions page. macOS has no
    /// in-app StoreKit manage-subscriptions sheet, so this routes to the App
    /// Store. Always returns; never throws.
    @MainActor
    public static func presentManageSubscriptions() async {
        await openFallbackURL()
    }
    #endif

    @MainActor
    private static func openFallbackURL() async {
        #if canImport(UIKit)
        _ = await UIApplication.shared.open(appleSubscriptionsURL)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(appleSubscriptionsURL)
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
