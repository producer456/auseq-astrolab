import SwiftUI
import UIKit

/// Guided, on-device test wizard for decoding the KeyLab. It walks you through
/// actuating each control, watches the chosen port live, shows what it detected,
/// captures it, and produces a copyable summary to hand back for mapping (M5).
struct ControllerLearnView: View {
    @ObservedObject var midi: MIDIManager
    var title: String = "Controller Learn"
    /// Each step = (label, instruction). Defaults to the M5 encoder/transport list.
    var stepDefs: [(title: String, hint: String)] = ControllerLearnView.defaultSteps

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let hint: String
    }

    private var steps: [Step] {
        stepDefs.enumerated().map { Step(id: $0.offset, title: $0.element.title, hint: $0.element.hint) }
    }

    static let defaultSteps: [(title: String, hint: String)] = {
        var s: [(String, String)] = []
        for i in 1...9 { s.append(("Encoder \(i)", "Twist encoder \(i) a little.")) }
        s.append(("Transport ▶ Play",  "Press PLAY."))
        s.append(("Transport ◼ Stop",  "Press STOP."))
        s.append(("Transport ● Record", "Press RECORD."))
        s.append(("Fader 1", "Move the first fader up and down."))
        return s
    }()

    /// The 10 left-of-screen DAW buttons we want to map.
    static let keylabButtonSteps: [(title: String, hint: String)] = [
        ("Save",        "Press the SAVE button."),
        ("Mute",        "Press the MUTE button."),
        ("Undo",        "Press the UNDO button."),
        ("Tap Tempo",   "Press the TAP (tempo) button."),
        ("Quantize",    "Press the QUANTIZE button."),
        ("Metronome",   "Press the METRO / CLICK button."),
        ("Preset Up",   "Press the button you want for PRESET UP (any unused left button)."),
        ("Preset Down", "Press the button you want for PRESET DOWN (any unused left button)."),
    ]

    @State private var index = 0
    @State private var port: String?
    @State private var counts: [String: Int] = [:]
    @State private var rep: [String: MIDIMonitorEntry] = [:]
    @State private var captured: [Int: MIDIMonitorEntry] = [:]
    @State private var finished = false
    @State private var copied = false

    private var current: Step { steps[min(index, steps.count - 1)] }
    private var candidateKey: String? { counts.max { $0.value < $1.value }?.key }
    private var candidate: MIDIMonitorEntry? { candidateKey.flatMap { rep[$0] } }

    var body: some View {
        Group { if finished { summary } else { stepView } }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { portMenu }
            }
            .onAppear {
                midi.isMonitoring = true
                port = midi.sourceNames.first { $0.localizedCaseInsensitiveContains("daw") } ?? midi.sourceNames.first
                midi.onMonitor = { e in receive(e) }
            }
            .onDisappear { midi.onMonitor = nil; midi.isMonitoring = false }
    }

    // MARK: - Step screen

    private var stepView: some View {
        VStack(spacing: 22) {
            ProgressView(value: Double(index), total: Double(steps.count))
                .tint(.orange)
            Text("Step \(index + 1) of \(steps.count)")
                .font(.caption).foregroundStyle(.secondary)

            Text(current.title).font(.system(size: 30, weight: .heavy, design: .rounded))
            Text(current.hint).font(.title3).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            detectionCard

            Spacer()

            HStack(spacing: 14) {
                Button("Skip") { advance() }
                    .buttonStyle(.bordered)
                Button(captured[current.id] == nil ? "Confirm & Next" : "Next") {
                    if let candidate { captured[current.id] = candidate }
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(candidate == nil)
            }
        }
        .padding(28)
    }

    private var detectionCard: some View {
        VStack(spacing: 8) {
            if let candidate {
                Text("DETECTED").font(.caption2).foregroundStyle(.secondary).tracking(2)
                Text(candidate.decoded)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
                Text(candidate.hex + "  ·  " + shortPort(candidate.source))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.largeTitle).foregroundStyle(.secondary)
                Text("Waiting for input on \(port.map(shortPort) ?? "any port")…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 120)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Summary screen

    private var summary: some View {
        VStack(spacing: 0) {
            List {
                ForEach(steps) { step in
                    HStack {
                        Text(step.title).font(.subheadline)
                        Spacer()
                        if let e = captured[step.id] {
                            Text(e.decoded).font(.system(size: 12, design: .monospaced)).foregroundStyle(.orange)
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            VStack(spacing: 10) {
                ShareLink(item: summaryText) {
                    Label("Share / AirDrop summary", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                Button {
                    UIPasteboard.general.string = summaryText
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy to clipboard",
                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private var summaryText: String {
        var lines = ["AUSeq \(title) — \(port.map(shortPort) ?? "all ports")"]
        for step in steps {
            let v = captured[step.id].map { "\($0.decoded)  [\($0.hex)]" } ?? "(skipped)"
            lines.append("\(step.title): \(v)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Capture

    private func receive(_ e: MIDIMonitorEntry) {
        guard !finished else { return }
        if let port, e.source != port { return }
        if e.status & 0xF0 == 0x80 { return }           // ignore note-offs
        if e.status & 0xF0 == 0x90 && e.d2 == 0 { return }
        let key = controlKey(e)
        counts[key, default: 0] += 1
        rep[key] = e
    }

    private func controlKey(_ e: MIDIMonitorEntry) -> String {
        let ch = e.status & 0x0F
        switch e.status & 0xF0 {
        case 0xB0: return "CC\(e.d1).\(ch)"
        case 0x90, 0x80: return "N\(e.d1).\(ch)"
        case 0xE0: return "PB.\(ch)"
        default: return "S\(e.status)"
        }
    }

    private func advance() {
        counts = [:]; rep = [:]
        if index >= steps.count - 1 { finished = true } else { index += 1 }
    }

    private var portMenu: some View {
        Menu {
            ForEach(midi.sourceNames, id: \.self) { p in
                Button(shortPort(p)) { port = p }
            }
            Button("All ports") { port = nil }
        } label: {
            Text(port.map(shortPort) ?? "All ports").font(.subheadline)
        }
    }

    private func shortPort(_ name: String) -> String {
        name.replacingOccurrences(of: "KeyLab mkII 88 ", with: "KL ")
            .replacingOccurrences(of: "Network Session 1", with: "Net")
    }
}
