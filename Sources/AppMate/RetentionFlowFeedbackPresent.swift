// One-call presentation of the native FeedbackView. The embeddable view lives
// in FeedbackView.swift; this just pops it as a sheet (iOS) or window (macOS).
// Both platforms — the web flow (presentURL / hosted page) remains an option.

#if canImport(UIKit) && canImport(SwiftUI)
import UIKit
import SwiftUI

extension RetentionFlow {
    /// Present the **native** feedback form as a sheet — the native alternative
    /// to opening the hosted web page. The form mirrors the published config
    /// (rating / message / email / custom fields).
    ///
    /// - Parameters:
    ///   - userId: Stable user id (optional; feedback is anonymous by default).
    ///   - flowSlug: Target a non-primary feedback flow. Omit for the default.
    ///   - presenter: VC to present from. Defaults to the top-most VC.
    ///   - onSubmitted: Called after a successful submit.
    @available(iOS 16.0, *)
    @MainActor
    public static func presentFeedback(
        userId: String? = nil,
        flowSlug: String? = nil,
        from presenter: UIViewController? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        guard let host = presenter ?? SafariPresenter.topViewController() else { return }
        let sheet = NavigationStack {
            FeedbackView(userId: userId, flowSlug: flowSlug, onSubmitted: onSubmitted)
                .navigationTitle("Feedback")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            host.presentedViewController?.dismiss(animated: true)
                        }
                    }
                }
        }
        let vc = UIHostingController(rootView: sheet)
        host.present(vc, animated: true)
    }
}

#elseif canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

extension RetentionFlow {
    // Retains the window so it isn't deallocated as soon as we return.
    nonisolated(unsafe) private static var feedbackWindowController: NSWindowController?

    /// Present the **native** feedback form in a window (macOS). Mirrors the
    /// published config (rating / message / email / custom fields).
    @available(macOS 13.0, *)
    @MainActor
    public static func presentFeedback(
        userId: String? = nil,
        flowSlug: String? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        let view = FeedbackView(userId: userId, flowSlug: flowSlug, onSubmitted: onSubmitted)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Feedback"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 580))
        let controller = NSWindowController(window: window)
        feedbackWindowController = controller
        controller.showWindow(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
