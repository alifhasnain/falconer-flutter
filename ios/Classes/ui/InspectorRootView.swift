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
    @ObservedObject var store: TransactionStore
    let onClose: () -> Void
    @State private var search = ""

    private var filtered: [HttpTransaction] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.transactions }
        return store.transactions.filter { tx in
            tx.url.lowercased().contains(query)
                || tx.method.lowercased().contains(query)
                || tx.host.lowercased().contains(query)
                || (tx.statusCode.map(String.init) ?? "").contains(query)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if store.transactions.isEmpty {
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
                    .disabled(store.transactions.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

/// A single transaction row: method · path, host, and status/timing.
struct TransactionRow: View {
    let tx: HttpTransaction

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
