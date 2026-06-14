#if canImport(UIKit)
import UIKit
import ObjectiveC.runtime

/// Detects the device-shake gesture from *any* screen without the host app
/// wiring anything into its view controllers.
///
/// iOS delivers `motionEnded(_:with:)` up the responder chain; if no view or
/// view controller consumes it, it reaches the `UIWindow`. We give `UIWindow`
/// its own `motionEnded` implementation (added at runtime, once) that fires our
/// callback on a shake and then forwards the event to the next responder so
/// system behaviours like shake-to-undo keep working.
///
/// This uses only public API (`class_addMethod` / `method_exchangeImplementations`)
/// — no private symbols — so it's App Store safe.
enum ShakeDetector {
    /// Invoked on the main thread when a shake completes. Set by
    /// ``RetentionFlow/enableShakeMenu(title:message:userId:items:)``.
    nonisolated(unsafe) static var onShake: (() -> Void)?

    private nonisolated(unsafe) static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true

        let real = #selector(UIResponder.motionEnded(_:with:))
        let ours = #selector(UIWindow.am_motionEnded(_:with:))
        guard let oursMethod = class_getInstanceMethod(UIWindow.self, ours) else {
            return
        }
        let imp = method_getImplementation(oursMethod)
        let types = method_getTypeEncoding(oursMethod)

        // UIWindow has no own `motionEnded` by default — give it ours. If a
        // future OS adds one, fall back to exchanging the two IMPs instead.
        if !class_addMethod(UIWindow.self, real, imp, types) {
            if let realMethod = class_getInstanceMethod(UIWindow.self, real) {
                method_exchangeImplementations(realMethod, oursMethod)
            }
        }
    }
}

extension UIWindow {
    @objc fileprivate func am_motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            ShakeDetector.onShake?()
        }
        // Keep the event flowing so shake-to-undo and any host handlers still
        // fire. When installed via `class_addMethod` this method *is* the
        // window's `motionEnded`, so `next` is the next responder up the chain.
        next?.motionEnded(motion, with: event)
    }
}
#endif
