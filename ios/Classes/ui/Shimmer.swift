#if DEBUG
import SwiftUI

/// One sweep across the whole placeholder group, not a per-block pulse.
///
/// PRODUCT.md principle 4 (restrained polish): the motion exists to say "the
/// shape of the data is already known, the data itself is a moment away" — a
/// single unhurried light pass, no bounce, no color. Mirrors the Compose
/// `ShimmerContainer` on Android so both platforms read as one product.
enum ShimmerMetrics {
    /// Seconds for the highlight to cross the container once.
    static let sweepDuration: Double = 1.5
    /// Width of the moving highlight band, as a fraction of the container width.
    static let bandFraction: CGFloat = 0.55
}

/// Wraps a group of `ShimmerBlock`s and runs a single diagonal light sweep
/// across all of them at once, so the group reads as one surface rather than a
/// grid of independently blinking boxes.
///
/// The band is composited with `.sourceAtop` inside a `compositingGroup()`, so
/// the highlight lands only on pixels the placeholders actually painted — the
/// background stays untouched.
///
/// Honours `accessibilityReduceMotion`: with motion reduced the placeholders
/// render static rather than animating.
struct ShimmerContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: CGFloat = 0

    private let label: String
    private let content: Content

    init(label: String = "Loading", @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        content
            .overlay(sweep)
            .compositingGroup()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .onAppear(perform: startSweep)
    }

    @ViewBuilder
    private var sweep: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { geo in
                LinearGradient(
                    gradient: Gradient(colors: [.clear, highlight, .clear]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: geo.size.width * ShimmerMetrics.bandFraction)
                .offset(x: offsetX(containerWidth: geo.size.width))
                .blendMode(.sourceAtop)
            }
            .allowsHitTesting(false)
        }
    }

    private func startSweep() {
        guard !reduceMotion else { return }
        withAnimation(
            .linear(duration: ShimmerMetrics.sweepDuration).repeatForever(autoreverses: false)
        ) {
            phase = 1
        }
    }

    /// Travels from fully off the leading edge to fully off the trailing edge.
    private func offsetX(containerWidth: CGFloat) -> CGFloat {
        let band = containerWidth * ShimmerMetrics.bandFraction
        return -band + phase * (containerWidth + band)
    }

    /// White reads as "light passing over"; dark mode needs far less of it.
    private var highlight: Color {
        Color.white.opacity(colorScheme == .dark ? 0.16 : 0.75)
    }
}

/// A single placeholder bar. `nil` width means "size to the parent".
///
/// The fill is a system fill color, so contrast stays correct in both light and
/// dark without a second palette.
struct ShimmerBlock: View {
    var width: CGFloat?
    var height: CGFloat = 12
    var corner: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: width, height: height)
    }
}
#endif
