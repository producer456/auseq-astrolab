import SwiftUI
import UIKit

/// Guided on-device verification for the v2.1 cross-pollination work (beat clock,
/// broadened MIDI, song save/load). Most of these need David's ears / hardware /
/// eyes, so this wizard gives explicit steps and captures a Pass/Fail/Note per
/// check, then hands back a copyable report. One check (the save/load round-trip)
/// runs automatically since it's pure serialization logic. See the guided-device-
/// testing pattern used by Controller Learn.
struct VerifyV21View: View {
    @ObservedObject var model: AppModel

    enum Result: String { case untested = "—", pass = "PASS", fail = "FAIL", skip = "SKIP" }

    private struct Check: Identifiable {
        let id: Int
        let title: String
        let needs: String          // what's required to run it
        let steps: [String]
        let auto: Bool             // app can decide pass/fail itself
    }

    private let checks: [Check] = [
        Check(id: 0, title: "Save/load round-trip",
              needs: "Nothing — runs in-app",
              steps: ["Tap “Run self-test”. The app encodes the current session to JSON, decodes it back, and verifies tracks, notes, tempo, grid, loop region, colours and instrument IDs all survive."],
              auto: true),
        Check(id: 1, title: "Plugin patch restore",
              needs: "One AUv3 instrument",
              steps: ["Load an instrument on a track and tweak a few of its parameters.",
                      "Top-bar folder → Save Song.",
                      "Change those parameters to something obviously different.",
                      "Folder → Open Last Song.",
                      "Confirm the plugin reloads AND the tweaked patch comes back (not the changed values)."],
              auto: false),
        Check(id: 2, title: "Beat-clock tempo change",
              needs: "Nothing — on-screen keys are fine",
              steps: ["Record a short loop (a few notes across a couple of bars).",
                      "Play it looping.",
                      "While it plays, change the tempo up and down.",
                      "Confirm playback stays in time and the playhead does NOT jump or stutter at the tempo change."],
              auto: false),
        Check(id: 3, title: "Aftertouch / program change",
              needs: "A controller that sends them",
              steps: ["Load an instrument that responds to aftertouch or program change.",
                      "Send channel/poly aftertouch (press into held keys) and/or a program-change message.",
                      "Confirm the instrument responds (timbre swell / patch change)."],
              auto: false),
        Check(id: 4, title: "External MIDI transport",
              needs: "A device/app sending MIDI Start/Stop",
              steps: ["Connect a clock source that sends MIDI real-time Start/Continue/Stop.",
                      "Hit Start on that device.",
                      "Confirm AUSeq’s transport starts, and Stop stops it."],
              auto: false),
    ]

    @State private var results: [Int: Result] = [:]
    @State private var notes: [Int: String] = [:]
    @State private var autoReport: String = ""
    @State private var copied = false

    var body: some View {
        List {
            ForEach(checks) { check in
                Section {
                    ForEach(Array(check.steps.enumerated()), id: \.offset) { i, step in
                        Label {
                            Text(step).font(.subheadline)
                        } icon: {
                            Text("\(i + 1)").font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.orange)
                        }
                    }

                    if check.auto {
                        Button { autoReport = model.roundTripReport() } label: {
                            Label("Run self-test", systemImage: "play.circle.fill")
                        }
                        if !autoReport.isEmpty {
                            Text(autoReport)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(autoReport.hasPrefix("PASS") ? .green : .red)
                        }
                    } else {
                        resultPicker(for: check.id)
                        TextField("Notes (optional)", text: noteBinding(check.id), axis: .vertical)
                            .font(.subheadline)
                    }
                } header: {
                    HStack {
                        Text(check.title)
                        Spacer()
                        Text(badge(for: check)).foregroundStyle(badgeColor(for: check))
                    }
                } footer: {
                    Text("Needs: \(check.needs)")
                }
            }

            Section {
                ShareLink(item: report) {
                    Label("Share / AirDrop report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy report", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Verify v2.1")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resultPicker(for id: Int) -> some View {
        Picker("Result", selection: Binding(
            get: { results[id] ?? .untested },
            set: { results[id] = $0 })) {
            Text("Pass").tag(Result.pass)
            Text("Fail").tag(Result.fail)
            Text("Skip").tag(Result.skip)
            Text("—").tag(Result.untested)
        }
        .pickerStyle(.segmented)
    }

    private func noteBinding(_ id: Int) -> Binding<String> {
        Binding(get: { notes[id] ?? "" }, set: { notes[id] = $0 })
    }

    private func badge(for check: Check) -> String {
        if check.auto { return autoReport.hasPrefix("PASS") ? "PASS" : (autoReport.isEmpty ? "—" : "FAIL") }
        return (results[check.id] ?? .untested).rawValue
    }

    private func badgeColor(for check: Check) -> Color {
        switch badge(for: check) {
        case "PASS": return .green
        case "FAIL": return .red
        case "SKIP": return .orange
        default: return .secondary
        }
    }

    private var report: String {
        var lines = ["AUSeq v2.1 — Verification report"]
        for check in checks {
            lines.append("[\(badge(for: check))] \(check.title)")
            if check.auto, !autoReport.isEmpty {
                for l in autoReport.split(separator: "\n") { lines.append("    \(l)") }
            }
            if let n = notes[check.id], !n.isEmpty { lines.append("    note: \(n)") }
        }
        return lines.joined(separator: "\n")
    }
}
