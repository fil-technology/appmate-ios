import Foundation
#if canImport(UIKit)
import UIKit
import SafariServices

/// Presents the AppMate hosted flow in an `SFSafariViewController` and
/// tracks per-user-flow navigation so deep links are caught the moment the
/// server emits a redirect.
@MainActor
final class SafariPresenter: NSObject, SFSafariViewControllerDelegate {
    static let shared = SafariPresenter()

    private weak var presented: SFSafariViewController?

    func present(
        url: URL,
        from presenter: UIViewController?,
        urlScheme: String,
        onAction: ((RetentionFlowDeepLink) -> Void)?
    ) {
        // Tear down any prior presentation defensively.
        presented?.dismiss(animated: false)

        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = false

        let svc = SFSafariViewController(url: url, configuration: config)
        svc.dismissButtonStyle = .close
        svc.modalPresentationStyle = .formSheet
        svc.delegate = self
        presented = svc

        DeepLinkObserver.shared.urlScheme = urlScheme
        DeepLinkObserver.shared.onAction = onAction

        let host = presenter ?? Self.topViewController()
        host?.present(svc, animated: true)
    }

    /// Best-effort search for a UIViewController to present from when the
    /// host app doesn't pass one explicitly.
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

        let window = scene?.windows.first(where: { $0.isKeyWindow })
            ?? scene?.windows.first

        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    // MARK: SFSafariViewControllerDelegate

    nonisolated func safariViewController(
        _ controller: SFSafariViewController,
        initialLoadDidRedirectTo URL: URL
    ) {
        // Each redirect inside the Safari view (intro → reason → response →
        // /leaving?to=...) flows through here. The /leaving page eventually
        // meta-refreshes to the {scheme}://retention-flow/... URL, but Safari
        // catches it first and we forward to our parser.
        Task { @MainActor in
            DeepLinkObserver.shared.handle(URL)
        }
    }

    nonisolated func safariViewControllerDidFinish(
        _ controller: SFSafariViewController
    ) {
        Task { @MainActor in
            DeepLinkObserver.shared.onAction = nil
        }
    }
}

/// Holds the active per-flow callback so `safariViewController(_:initialLoadDidRedirectTo:)`
/// has somewhere to deliver parsed actions.
@MainActor
final class DeepLinkObserver {
    static let shared = DeepLinkObserver()

    var urlScheme: String?
    var onAction: ((RetentionFlowDeepLink) -> Void)?

    func handle(_ url: URL) {
        guard let scheme = urlScheme,
              let parsed = RetentionFlowDeepLinkHandler.parse(
                url,
                expectedScheme: scheme
              )
        else { return }
        onAction?(parsed)
        // Dismiss the SafariView since we've handled the action.
        SafariPresenter.shared.dismissIfPresented()
    }
}

extension SafariPresenter {
    fileprivate func dismissIfPresented() {
        guard let presented else { return }
        presented.dismiss(animated: true) { [weak self] in
            self?.presented = nil
        }
    }

    /// Reachable from the public ``RetentionFlow/dismissFlow()`` entry
    /// point. Same logic as the fileprivate version above; split only so
    /// the internal callsite stays tightly scoped.
    func dismissIfPresentedPublic() {
        dismissIfPresented()
    }
}
#endif
