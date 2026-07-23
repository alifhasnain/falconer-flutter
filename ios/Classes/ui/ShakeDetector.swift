#if DEBUG
import Foundation
import UIKit

extension Notification.Name {
    /// Posted when a device shake is detected (debug only).
    static let falconerShake = Notification.Name("dev.alifhasnain.falconer.shake")
}

/// Shake-to-open — the idiomatic iOS debug entry point (iOS has no
/// notification-to-task model like Android). Debug-only: the whole file is
/// `#if DEBUG`, so nothing here is compiled into a release build.
///
/// Installs a `UIWindow`-scoped override of `motionEnded(_:with:)` that posts
/// `.falconerShake` on a shake, then forwards to the original implementation.
///
/// Why a block + captured IMP instead of the usual two-selector swizzle:
/// `UIResponder`'s default `motionEnded(_:with:)` forwards to the next responder
/// **using `_cmd`** (the selector it was invoked with). A classic swizzle calls
/// the original under a *renamed* selector, so that renamed selector gets
/// propagated up the chain to the window's next responder (`UIWindowScene`),
/// which does not implement it → `unrecognized selector` crash. Calling the
/// original IMP directly with the real `motionEnded:withEvent:` selector keeps
/// the responder chain intact and never leaks a private selector.
enum ShakeDetector {
    private static var installed = false
    private static var originalIMP: IMP?

    static func install() {
        guard !installed else { return }
        installed = true

        let selector = #selector(UIResponder.motionEnded(_:with:))
        guard let method = class_getInstanceMethod(UIWindow.self, selector) else { return }

        // Capture the inherited original BEFORE overriding.
        originalIMP = method_getImplementation(method)
        let typeEncoding = method_getTypeEncoding(method)

        let block: @convention(block) (UIWindow, UIEvent.EventSubtype, UIEvent?) -> Void = {
            window, motion, event in
            if motion == .motionShake {
                NotificationCenter.default.post(name: .falconerShake, object: nil)
            }
            // Forward with the CORRECT selector so the chain keeps working.
            if let originalIMP = originalIMP {
                typealias MotionFn = @convention(c) (UIWindow, Selector, UIEvent.EventSubtype, UIEvent?) -> Void
                let fn = unsafeBitCast(originalIMP, to: MotionFn.self)
                fn(window, selector, motion, event)
            }
        }

        // `class_replaceMethod` adds a UIWindow-scoped override (UIWindow has no
        // own motionEnded), so UIWindowScene / UIView / other responders are
        // untouched.
        class_replaceMethod(
            UIWindow.self, selector,
            imp_implementationWithBlock(block), typeEncoding
        )
    }
}
#endif
