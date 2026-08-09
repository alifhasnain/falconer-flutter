#if DEBUG
import SwiftUI
import UIKit

/// Detail screen: Overview / Request / Response tabs. Observes the store by id,
/// so a response or error merging in after the row was opened updates live.
struct TransactionDetailView: View {
    @ObservedObject var store: TransactionStore
    let id: String

    @State private var tab: Tab = .overview
    @State private var bodySearch = ""
    @State private var shareItem: ShareItem?
    /// The full row, read on demand. The store's published list is a projection
    /// without bodies, so detail fetches its own payload by id and re-fetches
    /// whenever the store republishes (`store.revision`).
    @State private var tx: HttpTransaction?
    @State private var loaded = false

    enum Tab: Hashable { case overview, request, response }

    var body: some View {
        Group {
            if let tx = tx {
                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        Text("Overview").tag(Tab.overview)
                        Text("Request").tag(Tab.request)
                        Text("Response").tag(Tab.response)
                    }
                    .pickerStyle(.segmented)
                    .padding(12)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch tab {
                            case .overview: OverviewTab(tx: tx)
                            case .request: RequestTab(tx: tx, query: $bodySearch)
                            case .response: ResponseTab(tx: tx, query: $bodySearch)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                }
                .background(FalconerTheme.background)
                .navigationTitle("\(tx.method) \(tx.path)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                shareItem = ShareItem(text: CurlBuilder.build(tx))
                            } label: {
                                Label("Share as cURL", systemImage: "terminal")
                            }
                            Button {
                                shareItem = ShareItem(text: TextExporter.export(tx))
                            } label: {
                                Label("Share as text", systemImage: "doc.plaintext")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .sheet(item: $shareItem) { item in
                    ShareSheet(items: [item.text])
                }
            } else if loaded {
                VStack {
                    Text("Transaction cleared")
                        .foregroundColor(FalconerTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FalconerTheme.background)
            } else {
                // The read has not answered yet — saying "cleared" here would be a
                // claim the data has not made (PRODUCT.md principle 3).
                FalconerTheme.background
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: store.revision) {
            tx = await store.transaction(id: id)
            loaded = true
        }
    }

    struct ShareItem: Identifiable {
        let id = UUID()
        let text: String
    }
}

// MARK: - Tabs

private struct OverviewTab: View {
    let tx: HttpTransaction

    var body: some View {
        DetailSection(title: "Overview") {
            KeyValueRow("Method", tx.method)
            KeyValueRow("URL", tx.url, monospaced: true)
            KeyValueRow("Status", statusText, color: FalconerTheme.statusColor(tx.statusCode))
            KeyValueRow("Started", BodyFormatting.formatTimestamp(tx.startedAt))
            KeyValueRow("Duration", BodyFormatting.formatDuration(tx.tookMs))
            KeyValueRow("Request size", BodyFormatting.formatBytes(tx.requestContentLength))
            KeyValueRow("Response size", BodyFormatting.formatBytes(tx.responseContentLength))
            if let proto = tx.protocolName { KeyValueRow("Protocol", proto) }
        }
        if let error = tx.error {
            DetailSection(title: "Error") {
                Text(error)
                    .font(FalconerTheme.mono)
                    .foregroundColor(FalconerTheme.statusColor(500))
                    .textSelection(.enabled)
            }
        }
    }

    private var statusText: String {
        if let code = tx.statusCode {
            return "\(code)\(tx.statusMessage.map { " \($0)" } ?? "")"
        }
        return tx.isFailure ? "Failed" : "In flight"
    }
}

private struct RequestTab: View {
    let tx: HttpTransaction
    @Binding var query: String

    var body: some View {
        HeadersSection(title: "Request headers", headers: tx.requestHeaders)
        BodySection(
            title: "Request body",
            bodyText: tx.requestBody,
            kind: tx.requestBodyKind,
            imageBytes: nil,
            query: $query
        )
    }
}

private struct ResponseTab: View {
    let tx: HttpTransaction
    @Binding var query: String

    var body: some View {
        HeadersSection(title: "Response headers", headers: tx.responseHeaders)
        BodySection(
            title: "Response body",
            bodyText: tx.responseBody,
            kind: tx.responseBodyKind ?? BodyKinds.none,
            imageBytes: tx.responseImageBytes,
            query: $query
        )
    }
}

// MARK: - Building blocks

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(FalconerTheme.textTertiary)
            VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(FalconerTheme.surface)
                .cornerRadius(10)
        }
    }
}

private struct KeyValueRow: View {
    let key: String
    let value: String
    var monospaced = false
    var color: Color = FalconerTheme.textPrimary

    init(_ key: String, _ value: String, monospaced: Bool = false, color: Color = FalconerTheme.textPrimary) {
        self.key = key
        self.value = value
        self.monospaced = monospaced
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.caption2)
                .foregroundColor(FalconerTheme.textTertiary)
            Text(value)
                .font(monospaced ? FalconerTheme.mono : .subheadline)
                .foregroundColor(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HeadersSection: View {
    let title: String
    let headers: [String: String]

    var body: some View {
        DetailSection(title: title) {
            if headers.isEmpty {
                Text("(no headers)")
                    .font(.footnote)
                    .foregroundColor(FalconerTheme.textTertiary)
            } else {
                ForEach(headers.sorted { $0.key < $1.key }, id: \.key) { key, value in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(key)
                            .font(FalconerTheme.monoSmall.weight(.semibold))
                            .foregroundColor(FalconerTheme.textSecondary)
                        Text(value)
                            .font(FalconerTheme.monoSmall)
                            .foregroundColor(redacted(value) ? FalconerTheme.textTertiary : FalconerTheme.textPrimary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func redacted(_ value: String) -> Bool { value == Redactor.redactedMarker }
}

/// Body rendering with visible markers, JSON pretty-print, search highlight and
/// image preview (PRODUCT.md principles 1 & 3: payload loudest; truncation /
/// redaction / unsupported always visibly marked).
private struct BodySection: View {
    let title: String
    let bodyText: String?
    let kind: String
    let imageBytes: Data?
    @Binding var query: String

    var body: some View {
        DetailSection(title: title) {
            HStack {
                KindBadge(kind: kind)
                Spacer()
            }

            if kind == BodyKinds.image, let data = imageBytes, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .cornerRadius(6)
                Text(BodyFormatting.formatBytes(Int64(data.count)))
                    .font(FalconerTheme.monoSmall)
                    .foregroundColor(FalconerTheme.textTertiary)
            } else if let text = displayText, !text.isEmpty {
                if marked(text) {
                    Label("Content truncated or not fully captured", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(FalconerTheme.statusColor(400))
                }
                TextField("Search in body", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.footnote)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                HighlightedText(text: text, query: query)
                    .textSelection(.enabled)
            } else {
                Text("(empty)")
                    .font(.footnote)
                    .foregroundColor(FalconerTheme.textTertiary)
            }
        }
    }

    /// Pretty-print JSON when possible, else the raw text.
    private var displayText: String? {
        guard let bodyText = bodyText else { return nil }
        if kind == BodyKinds.json, let pretty = BodyFormatting.prettyJSON(bodyText) {
            return pretty
        }
        return bodyText
    }

    private func marked(_ text: String) -> Bool {
        kind == BodyKinds.unsupported || text.contains("[Falconer:")
    }
}

private struct KindBadge: View {
    let kind: String

    var body: some View {
        Text(kind.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundColor(FalconerTheme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(FalconerTheme.background)
            .cornerRadius(4)
    }
}

/// Renders body text with case-insensitive search highlight. The match-finding
/// is the pure `BodyFormatting.matchRanges`; only the `AttributedString` styling
/// lives here.
private struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        Text(attributed)
            .font(FalconerTheme.mono)
            .foregroundColor(FalconerTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        var attributed = AttributedString(text)
        // Offsets come from `text`, whose character content is identical to
        // `attributed`, so they are always in-bounds.
        for range in BodyFormatting.matchRanges(in: text, query: query) {
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            let lower = attributed.index(attributed.startIndex, offsetByCharacters: start)
            let upper = attributed.index(lower, offsetByCharacters: length)
            attributed[lower..<upper].backgroundColor = FalconerTheme.highlight
        }
        return attributed
    }
}
#endif
