import SwiftUI

/// Configuration mode — the hub for all on-device testing/diagnostic tools.
/// New test flows get added here as sections so everything lives in one place.
struct ConfigurationView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("MIDI Controller") {
                    NavigationLink {
                        ControllerLearnView(midi: model.midi)
                    } label: {
                        Label("Controller Learn (guided)", systemImage: "checklist")
                    }
                    NavigationLink {
                        MIDIMonitorView(midi: model.midi)
                    } label: {
                        Label("Raw MIDI Monitor", systemImage: "dot.radiowaves.left.and.right")
                    }
                    NavigationLink {
                        KeyLabLCDView(midi: model.midi)
                    } label: {
                        Label("KeyLab LCD (experimental)", systemImage: "tv")
                    }
                }

                Section("Diagnostics") {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Live Event Log", systemImage: "waveform.path.ecg")
                    }
                }

                Section("Connected MIDI inputs") {
                    if model.midi.sourceNames.isEmpty {
                        Text("None — connect a controller").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.midi.sourceNames, id: \.self) { name in
                            Text(name).font(.system(.footnote, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
