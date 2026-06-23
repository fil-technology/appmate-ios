// One-call presentation of the native ContactView. The embeddable view lives in
// ContactView.swift; this pops it as a sheet (iOS) or window (macOS). The web
// flow (presentURL / hosted page) remains an option.

#if canImport(UIKit) && canImport(SwiftUI)
import UIKit
import SwiftUI

extension RetentionFlow {
    /// Present the **native** contact form as a sheet — the native alternative
    /// to opening the hosted web page. Renders the published config (name /
    /// email / message toggles + custom fields).
    ///
    /// - Parameters:
    ///   - userId: Stable user id (optional).
    ///   - flowSlug: Target a non-primary contact flow. Omit for the default.
    ///   - presenter: VC to present from. Defaults to the top-most VC.
    ///   - onSubmitted: Called after a successful submit.
    @available(iOS 16.0, *)
    @MainActor
    public static func presentContact(
        userId: String? = nil,
        flowSlug: String? = nil,
        from presenter: UIViewController? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        guard let host = presenter ?? SafariPresenter.topViewController() else { return }
        let sheet = NavigationStack {
            ContactView(userId: userId, flowSlug: flowSlug, onSubmitted: onSubmitted)
                .navigationTitle("Contact")
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
    nonisolated(unsafe) private static var contactWindowController: NSWindowController?

    /// Present the **native** contact form in a window (macOS).
    @available(macOS 13.0, *)
    @MainActor
    public static func presentContact(
        userId: String? = nil,
        flowSlug: String? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        let view = ContactView(userId: userId, flowSlug: flowSlug, onSubmitted: onSubmitted)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Contact"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 580))
        let controller = NSWindowController(window: window)
        contactWindowController = controller
        controller.showWindow(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
