#if DEBUG
import SwiftUI

/// Loading placeholder for the inspector list.
///
/// Geometry mirrors `TransactionRow` — same stack, same spacing, same row
/// insets, same divider — so the real rows land where the placeholders were with
/// no visible reflow (PRODUCT.md principle 2: the eye is already parked on the
/// hot path when the data arrives).
struct TransactionListSkeleton: View {
    /// Uneven path widths keep the placeholder reading as a list of *different*
    /// requests rather than a repeating pattern. Fixed, not random, so the
    /// skeleton is stable across re-renders.
    private static let pathFractions: [CGFloat] = [0.62, 0.44, 0.78, 0.53, 0.70, 0.38, 0.66, 0.50]

    var rows: Int = 7

    var body: some View {
        GeometryReader { geo in
            ShimmerContainer(label: "Loading requests") {
                VStack(spacing: 0) {
                    ForEach(Array(0..<rows), id: \.self) { index in
                        SkeletonRow(
                            available: max(geo.size.width - 32, 0),
                            pathFraction: Self.pathFractions[index % Self.pathFractions.count]
                        )
                        Divider()
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(FalconerTheme.background)
    }
}

/// One placeholder row: method · status · duration, then path, then host.
private struct SkeletonRow: View {
    let available: CGFloat
    let pathFraction: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ShimmerBlock(width: 46, height: 12)   // method
                ShimmerBlock(width: 30, height: 12)   // status
                Spacer(minLength: 8)
                ShimmerBlock(width: 44, height: 10)   // duration
            }
            ShimmerBlock(width: available * pathFraction, height: 14)            // path
            ShimmerBlock(width: available * pathFraction * 0.55, height: 10)     // host
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
#endif
