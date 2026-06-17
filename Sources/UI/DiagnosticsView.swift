import SwiftUI

/// Live diagnostics log (Configuration). Shows app/audio/sequencer events as
/// they happen so we can debug device-only behavior, with Share/AirDrop to send
/// the whole log back.
struct DiagnosticsView: View {
    @ObservedObject var log = DiagLog.shared

    private var shown: [DiagLog.Entry] { Array(log.entries.suffix(300).reversed()) }

    @State private var trace = DiagLog.shared.lastBreadcrumbs

    var body: some View {
        ScrollView {
            DisclosureGroup {
                Text(trace)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
                HStack {
                    ShareLink(item: trace) { Label("Share trace", systemImage: "square.and.arrow.up") }
                    Spacer()
                    Button("Refresh") { trace = DiagLog.shared.lastBreadcrumbs }
                }
                .font(.caption).padding(.top, 4)
            } label: {
                Label("Last load trace (after a crash)", systemImage: "ant.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            }
            .padding(.horizontal, 12).padding(.top, 8)

            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(shown) { e in
                    HStack(alignment: .top, spacing: 8) {
                        Text(time(e.time))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            .frame(width: 88, alignment: .leading)
                        Text(e.category.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(color(e.category))
                            .frame(width: 52, alignment: .leading)
                        Text(e.message).font(.system(size: 11, design: .monospaced))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 1)
                }
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: log.text) { Image(systemName: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .primaryAction) { Button("Clear") { log.clear() } }
        }
    }

    private func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: d)
    }

    private func color(_ category: String) -> Color {
        switch category {
        case "audio": return .orange
        case "seq":   return .blue
        case "app":   return .green
        default:      return .secondary
        }
    }
}
