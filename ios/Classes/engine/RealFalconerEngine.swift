#if DEBUG
import Foundation
import UIKit

/// The full inspector engine — compiled ONLY in debug builds.
///
/// Owns the `TransactionStore` (capture + storage + live count) and the SwiftUI
/// presentation. The thin plugin talks only to the `FalconerEngine` protocol, so
/// none of this is reachable from a release build.
final class RealFalconerEngine: FalconerEngine {
    private let store = TransactionStore()
    private lazy var presenter = InspectorPresenter(store: store)
    private var shakeObserver: NSObjectProtocol?

    func attach() {
        DispatchQueue.main.async { [weak self] in
            ShakeDetector.install()
            self?.shakeObserver = NotificationCenter.default.addObserver(
                forName: .falconerShake, object: nil, queue: .main
            ) { [weak self] _ in
                self?.presenter.present()
            }
        }
    }

    func detach() {
        DispatchQueue.main.async { [weak self] in
            if let observer = self?.shakeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self?.presenter.dismiss()
        }
    }

    func configure(_ args: [String: Any]) {
        store.configure(args)
    }

    func logRequest(_ args: [String: Any]) {
        store.ingestRequest(args)
    }

    func logResponse(_ args: [String: Any]) {
        store.ingestResponse(args)
    }

    func logError(_ args: [String: Any]) {
        store.ingestError(args)
    }

    func clear() {
        store.clear()
        DispatchQueue.main.async { [weak self] in self?.presenter.dismiss() }
    }

    func launchUi() {
        DispatchQueue.main.async { [weak self] in self?.presenter.present() }
    }

    func observeCount() -> AsyncStream<Int> {
        store.observeCount()
    }
}
#endif
