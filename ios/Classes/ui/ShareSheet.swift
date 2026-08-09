#if DEBUG
import SwiftUI
import UIKit

/// Thin SwiftUI wrapper over `UIActivityViewController` for export/share
/// (cURL / text). iOS's share sheet replaces Android's `Intent` share.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
