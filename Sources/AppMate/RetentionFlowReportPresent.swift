// One-call presentation of the native ReportView. The embeddable view lives in
// ReportView.swift; this pops it as a sheet (iOS) or window (macOS). The web
// flow (presentURL / hosted page) remains an option.

#if canImport(UIKit) && canImport(SwiftUI)
import UIKit
import SwiftUI

extension RetentionFlow {
    /// Present the **native** report form as a sheet — the native alternative
    /// to opening the hosted web page. Renders the published config (category
    /// list + message + optional email).
    ///
    /// - Parameters:
    ///   - userId: Stable user id (optional; reports are anonymous by default).
    ///   - flowSlug: Target a non-primary report flow. Omit for the default.
    ///   - presenter: VC to present from. Defaults to the top-most VC.
    ///   - onSubmitted: Called after a successful submit.
    @available(iOS 16.0, *)
    @MainActor
    public static func presentReport(
        userId: String? = nil,
        flowSlug: String? = nil,
        from presenter: UIViewController? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        guard let host = presenter ?? SafariPresenter.topViewController() else { return }
        let sheet = NavigationStack {
            ReportView(userId: userId, flowSlug: flowSlug, onSubmitted: onSubmitted)
                .navigationTitle("Report")
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
    nonisolated(unsafe) private static var reportWindowController: NSWindowController?

    /// Present the **native** report form in a window (macOS).
    @available(macOS 13.0, *)
    @MainActor
    public static func presentReport(
        userId: String? = nil,
        flowSlug: String? = nil,
        onSubmitted: (() -> Void)? = nil
    ) {
        let view = ReportView(userId: userId, flowSlug: flowSlug, onSubmitted: onSubmitted)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Report"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 440, height: 580))
        let controller = NSWindowController(window: window)
        reportWindowController = controller
        controller.showWindow(nil)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
