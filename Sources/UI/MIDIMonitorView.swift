import SwiftUI

/// Raw-MIDI monitor (M5 tool). Streams every incoming message tagged with its
/// source port so we can decode the KeyLab DAW port — encoders, transport, and
/// the handshake. Filter to a single port to isolate the DAW stream.
struct MIDIMonitorView: View {
    @ObservedObject var midi: MIDIManager
    @State private var portFilter: String? = nil

    private var ports: [String] {
        Array(Set(midi.monitorEntries.map(\.source))).sorted()
    }

    private var filtered: [MIDIMonitorEntry] {
        portFilter == nil ? midi.monitorEntries
                          : midi.monitorEntries.filter { $0.source == portFilter }
    }

    private var shown: [MIDIMonitorEntry] {
        Array(filtered.suffix(300).reversed())
    }

    /// Chronological text dump for Share / AirDrop.
    private var logText: String {
        let header = "AUSeq MIDI Monitor — \(portFilter.map(shortPort) ?? "all ports")"
        let lines = filtered.suffix(400).map { "\($0.hex)  \($0.decoded)  [\(shortPort($0.source))]" }
        return ([header] + lines).joined(separator: "\n")
    }

    var body: some View {
            VStack(spacing: 0) {
                controls
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(shown) { e in
                            HStack(spacing: 10) {
                                Text(e.hex)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .frame(width: 72, alignment: .leading)
                                Text(e.decoded)
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Text(shortPort(e.source))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 1)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("MIDI Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: logText) { Image(systemName: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .primaryAction) { Button("Clear") { midi.clearMonitor() } }
            }
            .onAppear { midi.isMonitoring = true }
            .onDisappear { midi.isMonitoring = false }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Menu {
                Button("All ports") { portFilter = nil }
                ForEach(ports, id: \.self) { p in
                    Button(shortPort(p)) { portFilter = p }
                }
            } label: {
                Label(portFilter.map(shortPort) ?? "All ports", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline)
            }
            Spacer()
            Text("\(shown.count) msgs")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    /// Trim the verbose CoreMIDI display name for the row tag.
    private func shortPort(_ name: String) -> String {
        name.replacingOccurrences(of: "KeyLab mkII 88 ", with: "KL ")
            .replacingOccurrences(of: "Network Session 1", with: "Net")
    }
}
