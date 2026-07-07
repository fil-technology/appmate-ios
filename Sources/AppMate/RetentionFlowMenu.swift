import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Shake-to-open "feedback menu".
//
// Enable it once at launch with the flows you want to expose:
//
//     RetentionFlow.enableShakeMenu(items: [
//         .suggestFeature(),
//         .reportBug(),
//         .contact(),
//     ])
//
// From then on, a device shake on *any* screen presents a bottom sheet listing
// those options. Tapping one opens that flow (native wishlist board, or the
// hosted contact/report/feedback page in a Safari sheet). You can also present
// the same menu yourself from a button via ``RetentionFlow/presentMenu(...)``.
// ─────────────────────────────────────────────────────────────────────────────

/// One row in the shake "feedback menu". Build these with the convenience
/// factories (``suggestFeature(title:subtitle:systemImage:flowSlug:)`` etc.) —
/// each maps to one of your AppMate flows.
public struct RetentionFlowMenuItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let subtitle: String?
    /// SF Symbol name shown in the row's leading icon.
    public let systemImage: String
    let action: Action

    enum Action {
        case wishlist(flowSlug: String?)          // native WishlistView
        case crash(flowSlug: String?)             // native CrashReportView
        case cancel                               // session bootstrap → Safari
        case web(WebFlow, flowSlug: String?)      // hosted page → Safari
        case custom(@MainActor () -> Void)        // host-provided escape hatch
    }

    enum WebFlow: String {
        case contact, report, feedback, wishlist, waitlist, linkPage
    }

    init(
        title: String,
        subtitle: String?,
        systemImage: String,
        action: Action
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.action = action
    }
}

extension RetentionFlowMenuItem {
    /// Open the native feature-wishlist board (suggest + upvote).
    public static func suggestFeature(
        title: String = "Suggest a feature",
        subtitle: String? = nil,
        systemImage: String = "lightbulb",
        flowSlug: String? = nil
    ) -> RetentionFlowMenuItem {
        .init(title: title, subtitle: subtitle, systemImage: systemImage,
              action: .wishlist(flowSlug: flowSlug))
    }

    /// Open the hosted bug-report form.
    public static func reportBug(
        title: String = "Report a bug",
        subtitle: String? = nil,
        systemImage: String = "ladybug",
        flowSlug: String? = nil
    ) -> RetentionFlowMenuItem {
        .init(title: title, subtitle: subtitle, systemImage: systemImage,
              action: .web(.report, flowSlug: flowSlug))
    }

    /// Open the native crash-report form (device diagnostics attached, and a
    /// crash captured by ``RetentionFlow/enableCrashDetection()`` pre-filled).
    public static func reportCrash(
        title: String = "Report a crash",
        subtitle: String? = nil,
        systemImage: String = "exclamationmark.triangle",
        flowSlug: String? = nil
    ) -> RetentionFlowMenuItem {
        .init(title: title, subtitle: subtitle, systemImage: systemImage,
              action: .crash(flowSlug: flowSlug))
    }

    /// Open the hosted contact / support form.
    public static func contact(
        title: String = "Contact us",
        subtitle: String? = nil,
        systemImage: String = "envelope",
        flowSlug: String? = nil
    ) -> RetentionFlowMenuItem {
        .init(title: title, subtitle: subtitle, systemImage: systemImage,
              action: .web(.contact, flowSlug: flowSlug))
    }

    /// Open the hosted feedback form (rating + message).
    public static func feedback(
        title: String = "Send feedback",
        subtitle: String? = nil,
        systemImage: String = "star.bubble",
        flowSlug: String? = nil
    ) -> RetentionFlowMenuItem {
        .init(title: title, subtitle: subtitle, systemImage: systemImage,
              action: .web(.feedback, flowSlug: flowSlug))
    }

    /// Open the cancel-subscription flow.
    public static func cancelSubscription(
        title: String = "Cancel subscription",
        subtitle: String? = nil,
        systemImage: String = "xmark.circle"
    ) -> RetentionFlowMenuItem {
        .init(title: title, subtitle: subtitle, systemImage: systemImage,
              action: .cancel)
    }

    /// A fully custom row — run any code you like (open your own screen,
    /// pre-fill state, etc.).
    public static func custom(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "ellipsis.circle",
        action: @escaping @MainActor () -> Void
    ) -> RetentionFlowMenuItem {
        .init(title: title, subtitle: subtitle, systemImage: systemImage,
              action: .custom(action))
    }
}

#if canImport(UIKit) && canImport(SwiftUI)
extension RetentionFlow {

    // MARK: Stored menu configuration

    nonisolated(unsafe) private static var _menuItems: [RetentionFlowMenuItem] = []
    nonisolated(unsafe) private static var _menuTitle = "Help us improve"
    nonisolated(unsafe) private static var _menuMessage: String? = "Pick a way to reach us."
    nonisolated(unsafe) private static var _menuUserId: String?
    nonisolated(unsafe) private static var _shakeEnabled = false
    nonisolated(unsafe) private static weak var _menuVC: UIViewController?

    // MARK: Public entry points

    /// Turn on shake-to-open. After this call, a device shake on any screen
    /// presents a bottom sheet with the given `items`. Call once at launch
    /// (after ``configure(_:)``).
    ///
    /// - Parameters:
    ///   - title: Sheet heading.
    ///   - message: Optional one-line subheading. Pass `nil` to hide it.
    ///   - userId: Stable user id forwarded to whichever flow opens (for
    ///     vote/comment dedup and session attribution). Optional.
    ///   - items: The flows to list, top to bottom.
    ///
    /// Safe to call from your `App.init()` / app delegate — it only stores
    /// config and installs the (idempotent) shake detector; presentation hops
    /// to the main actor when a shake actually fires.
    public static func enableShakeMenu(
        title: String = "Help us improve",
        message: String? = "Pick a way to reach us.",
        userId: String? = nil,
        items: [RetentionFlowMenuItem]
    ) {
        _menuTitle = title
        _menuMessage = message
        _menuUserId = userId
        _menuItems = items
        _shakeEnabled = true

        ShakeDetector.onShake = {
            // motionEnded already runs on the main thread, but hop explicitly
            // so we satisfy the main-actor presentation requirement.
            Task { @MainActor in
                guard _shakeEnabled else { return }
                presentMenu()
            }
        }
        ShakeDetector.install()
    }

    /// Stop responding to shakes. The detector stays installed (cheap) but
    /// becomes inert.
    public static func disableShakeMenu() {
        _shakeEnabled = false
    }

    /// Present the feedback menu programmatically (e.g. from a "Feedback"
    /// button) using the items configured in ``enableShakeMenu(...)``, or an
    /// explicit `items` list passed here.
    @MainActor
    public static func presentMenu(
        items: [RetentionFlowMenuItem]? = nil,
        title: String? = nil,
        message: String? = nil,
        userId: String? = nil,
        from presenter: UIViewController? = nil
    ) {
        // Don't stack menus.
        if _menuVC != nil { return }

        let resolvedItems = items ?? _menuItems
        guard !resolvedItems.isEmpty else { return }
        let resolvedUserId = userId ?? _menuUserId

        let host = presenter ?? SafariPresenter.topViewController()
        guard let host else { return }

        let view = RetentionFlowMenuView(
            title: title ?? _menuTitle,
            message: message ?? _menuMessage,
            items: resolvedItems,
            onSelect: { item in
                // Dismiss the sheet first, then run the action from a clean
                // top-most presenter so the next sheet animates correctly.
                _menuVC?.dismiss(animated: true) {
                    _menuVC = nil
                    Task { @MainActor in perform(item, userId: resolvedUserId) }
                }
            },
            onClose: {
                _menuVC?.dismiss(animated: true) { _menuVC = nil }
            }
        )

        let vc = UIHostingController(rootView: view)
        vc.view.backgroundColor = .clear
        if let sheet = vc.sheetPresentationController {
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
            // Size the sheet to its content: header + one row per item.
            let estimated = CGFloat(96 + resolvedItems.count * 68 + 24)
            sheet.detents = [
                .custom(identifier: .init("appmate.menu")) { ctx in
                    min(estimated, ctx.maximumDetentValue)
                },
                .large(),
            ]
        }
        _menuVC = vc
        host.present(vc, animated: true)
    }

    // MARK: Routing

    @MainActor
    private static func perform(_ item: RetentionFlowMenuItem, userId: String?) {
        switch item.action {
        case .wishlist(let flowSlug):
            presentWishlist(userId: userId, flowSlug: flowSlug)
        case .crash(let flowSlug):
            presentCrashReport(userId: userId, flowSlug: flowSlug)
        case .cancel:
            startCancelFlow(userId: userId)
        case .web(let flow, let flowSlug):
            guard let url = webURL(for: flow, flowSlug: flowSlug) else { return }
            presentURL(url)
        case .custom(let action):
            action()
        }
    }

    /// Present the **native** in-app feature-wishlist board as a sheet — the
    /// drop-in equivalent of ``startCancelFlow(...)`` for wishlists. Use this
    /// when you just want the board up from a button or menu and don't want to
    /// place ``WishlistView`` in your own hierarchy.
    ///
    /// For an iOS app this is almost always what you want instead of linking
    /// the hosted web board: it renders natively, votes/comments dedupe by
    /// `userId`, and there's no Safari bounce.
    ///
    /// - Parameters:
    ///   - userId: Stable user id for cross-device vote/comment dedup. Optional.
    ///   - flowSlug: Target a non-primary wishlist flow. Omit for the default.
    ///   - presenter: VC to present from. Defaults to the top-most VC.
    @MainActor
    public static func presentWishlist(
        userId: String? = nil,
        flowSlug: String? = nil,
        from presenter: UIViewController? = nil
    ) {
        guard let host = presenter ?? SafariPresenter.topViewController() else { return }
        let sheet = NavigationStack {
            WishlistView(userId: userId, flowSlug: flowSlug)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { host.presentedViewController?.dismiss(animated: true) }
                    }
                }
        }
        let vc = UIHostingController(rootView: sheet)
        host.present(vc, animated: true)
    }

    /// Build the hosted URL for a web flow from ``RetentionFlowConfig/webBaseURL``
    /// (or a value derived from `baseURL`).
    static func webURL(for flow: RetentionFlowMenuItem.WebFlow, flowSlug: String?) -> URL? {
        guard let config = config else { return nil }
        let base = webBaseURL(from: config)
        let segment: String
        switch flow {
        case .contact:  segment = "contact"
        case .report:   segment = "report"
        case .feedback: segment = "feedback"
        case .wishlist: segment = "wishlist"
        case .waitlist: segment = "waitlist"
        case .linkPage: segment = "p"
        }
        var url = base
            .appendingPathComponent(segment)
            .appendingPathComponent(config.appSlug)
        if let flowSlug, !flowSlug.isEmpty {
            url = url.appendingPathComponent(flowSlug)
        }
        return url
    }

    /// Apex host for web flow pages: explicit `webBaseURL` if set, else
    /// `baseURL` with a leading `cancel.` / `flow.` / `signup.` label removed.
    static func webBaseURL(from config: RetentionFlowConfig) -> URL {
        if let explicit = config.webBaseURL { return explicit }
        guard
            var comps = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false),
            let host = comps.host
        else { return config.baseURL }
        for prefix in ["cancel.", "flow.", "signup."] where host.hasPrefix(prefix) {
            comps.host = String(host.dropFirst(prefix.count))
            return comps.url ?? config.baseURL
        }
        return config.baseURL
    }
}

// MARK: - Bottom-sheet UI

/// The shake menu's content. A heading, an optional subheading, and one tappable
/// row per flow. Presented inside a `UISheetPresentationController` so it reads
/// as a native bottom sheet.
struct RetentionFlowMenuView: View {
    let title: String
    let message: String?
    let items: [RetentionFlowMenuItem]
    let onSelect: (RetentionFlowMenuItem) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(items) { item in
                    Button { onSelect(item) } label: {
                        RetentionFlowMenuRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Button("Not now", action: onClose)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
}

private struct RetentionFlowMenuRow: View {
    let item: RetentionFlowMenuItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
    }
}
#endif
