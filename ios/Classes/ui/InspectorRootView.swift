#if DEBUG
import SwiftUI

/// The inspector's list screen — reverse-chronological transactions with
/// filter-as-you-type. Triage speed is the hot path (PRODUCT.md principle 2):
/// list → tap → detail, one thumb-reach away.
///
/// `NavigationView(.stack)` (not `NavigationStack`) because the deployment
/// target is iOS 15; the destination observes the store so a response merging
/// in after the row is opened updates the open detail live.
struct InspectorRootView: View {
    /// How long the screen may stay loading before the skeleton appears. Under
    /// this, the data wins the race and no placeholder is ever drawn — a
    /// one-frame flash of shimmer is noise, not polish.
    private static let skeletonGrace: TimeInterval = 0.12
    /// Once shown, the skeleton holds this long so it reads as a state, not a blink.
    private static let skeletonMinHold: TimeInterval = 0.32

    @ObservedObject var store: TransactionStore
    let onClose: () -> Void
    @State private var search = ""
    @State private var showSkeleton = false
    @State private var skeletonShownAt = Date()

    private var filtered: [TransactionListRow] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.rows }
        return store.rows.filter { tx in
            tx.url.lowercased().contains(query)
                || tx.method.lowercased().contains(query)
                || tx.host.lowercased().contains(query)
                || (tx.statusCode.map(String.init) ?? "").contains(query)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if showSkeleton {
                    TransactionListSkeleton()
                } else if store.rows.isEmpty {
                    EmptyStateView()
                } else {
                    List {
                        ForEach(filtered) { tx in
                            NavigationLink {
                                TransactionDetailView(store: store, id: tx.id)
                            } label: {
                                TransactionRow(tx: tx)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(FalconerTheme.background)
            .animation(.easeInOut(duration: 0.18), value: showSkeleton)
            .task(id: store.isLoading) { await syncSkeleton() }
            .navigationTitle("Falconer")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $search,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Filter by URL, method, status"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(store.rows.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    /// Debounces `store.isLoading` into skeleton visibility.
    ///
    /// `.task(id:)` cancels this on every change of the flag, which is what
    /// implements the grace window: if the load finishes inside it, the pending
    /// "show" is cancelled before it fires and no placeholder is ever drawn.
    private func syncSkeleton() async {
        if store.isLoading {
            try? await Task.sleep(nanoseconds: UInt64(Self.skeletonGrace * 1_000_000_000))
            guard !Task.isCancelled else { return }
            skeletonShownAt = Date()
            showSkeleton = true
        } else if showSkeleton {
            let elapsed = Date().timeIntervalSince(skeletonShownAt)
            if elapsed < Self.skeletonMinHold {
                try? await Task.sleep(
                    nanoseconds: UInt64((Self.skeletonMinHold - elapsed) * 1_000_000_000)
                )
            }
            guard !Task.isCancelled else { return }
            showSkeleton = false
        }
    }
}

/// A single transaction row: method · path, host, and status/timing.
struct TransactionRow: View {
    let tx: TransactionListRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(tx.method.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundColor(FalconerTheme.methodColor(tx.method))
                    .frame(minWidth: 46, alignment: .leading)
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(FalconerTheme.statusColor(tx.statusCode))
                Spacer()
                Text(BodyFormatting.formatDuration(tx.tookMs))
                    .font(FalconerTheme.monoSmall)
                    .foregroundColor(FalconerTheme.textTertiary)
            }
            Text(tx.path.isEmpty ? tx.url : tx.path)
                .font(.subheadline)
                .foregroundColor(FalconerTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(tx.host)
                .font(.caption2)
                .foregroundColor(FalconerTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        if let code = tx.statusCode { return "\(code)" }
        if tx.isFailure { return "ERR" }
        return "···"
    }
}

/// Empty state — honest and quiet, not decorative.
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(FalconerTheme.textTertiary)
            Text("No requests captured yet")
                .font(.headline)
                .foregroundColor(FalconerTheme.textSecondary)
            Text("Make a request through a Dio client with FalconerInterceptor attached.")
                .font(.footnote)
                .foregroundColor(FalconerTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FalconerTheme.background)
    }
}
#endif
