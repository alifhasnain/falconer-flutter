#if DEBUG
import SwiftUI
import UIKit

/// Hosts the SwiftUI inspector in its own `UIWindow` so it overlays whatever the
/// app is showing, then tears the window down on close. One window at a time;
/// re-presenting while visible is a no-op.
final class InspectorPresenter {
    private let store: TransactionStore
    private var window: UIWindow?

    init(store: TransactionStore) {
        self.store = store
    }

    func present() {
        guard window == nil, let scene = activeScene() else { return }
        let root = InspectorRootView(store: store) { [weak self] in self?.dismiss() }
        let host = UIHostingController(rootView: root)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        self.window = window
    }

    func dismiss() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }

    private func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
#endif
