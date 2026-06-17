import SwiftUI

/// Transport strip (M6) — driven by both the KeyLab's transport buttons and
/// these on-screen controls. Shows Stop / Play / Record and the position clock.
/// Sits on the wood deck with its controls milled in (inlaid wells).
struct TransportBar: View {
    @ObservedObject var seq: Sequencer
    var onQuantizeSelected: () -> Void = {}
    var onQuantizeAll: () -> Void = {}
    var compact: Bool = false
    var tone: WoodTone = .oak

    var body: some View {
        // No background — sits on the shared wood panel provided by the parent.
        if compact {
            ScrollView(.horizontal, showsIndicators: false) { controls }
        } else {
            controls
        }
    }

    private var controls: some View {
        HStack(spacing: compact ? 10 : 14) {
            // Stop / Play / Record — metal LED buttons
            Button { seq.stop() } label: {
                InlaidMetalButton(system: "stop.fill", lit: true, tint: Color(red: 0.55, green: 0.68, blue: 0.82), size: 42, tone: tone)
            }.buttonStyle(.plain)
            Button { seq.play() } label: {
                InlaidMetalButton(system: "play.fill", lit: seq.isPlaying, tint: Theme.orange, size: 42, tone: tone)
            }.buttonStyle(.plain)
            Button { seq.toggleRecord() } label: {
                InlaidMetalButton(system: "record.circle", lit: seq.isRecordArmed, tint: .red, size: 42, tone: tone)
            }.buttonStyle(.plain)

            Text(seq.positionLabel)
                .font(Theme.mono(18, .bold))
                .foregroundStyle(tone.ink)
                .monospacedDigit()
                .frame(width: 54, alignment: .leading)
                .padding(.leading, 2)

            // Beat dots
            HStack(spacing: 4) {
                ForEach(0..<seq.beatsPerBar, id: \.self) { i in
                    Circle()
                        .fill(seq.isPlaying && i == seq.beatInBar
                              ? (i == 0 ? Theme.orange : tone.ink)
                              : tone.ink.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }

            if !compact { Spacer() }

            // Loop / metronome / count-in — metal LED toggles
            iconToggle("repeat", on: seq.loopEnabled) { seq.loopEnabled.toggle() }
            iconToggle("metronome", on: seq.metronomeOn) { seq.metronomeOn.toggle() }
            iconToggle("timer", on: seq.countInEnabled) { seq.countInEnabled.toggle() }

            // Quantize menu — metal readout pill
            Menu {
                Picker("Grid", selection: $seq.quantizeGrid) {
                    ForEach(QuantizeGrid.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Auto-quantize while recording", isOn: $seq.quantizeOn)
                Divider()
                Button("Quantize selected track", action: onQuantizeSelected)
                Button("Quantize all tracks", action: onQuantizeAll)
            } label: {
                Text("Q \(seq.quantizeGrid.rawValue)")
                    .font(Theme.mono(12, .bold))
                    .foregroundStyle(seq.quantizeOn ? Theme.orange : Theme.etched)
                    .metalInlayPill(tone: tone, hPad: 9, vPad: 8)
            }

            // Tempo — metal readout pill with -/+ and BPM
            HStack(spacing: 8) {
                Button { seq.bpm = max(40, seq.bpm - 1) } label: {
                    Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.orange)
                }
                Text("\(Int(seq.bpm))").font(Theme.mono(13, .bold)).foregroundStyle(Theme.etched).frame(width: 30)
                Button { seq.bpm = min(240, seq.bpm + 1) } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.orange)
                }
            }
            .metalInlayPill(tone: tone, hPad: 10, vPad: 8)

            // Loop length (bars) — metal readout pill
            Menu {
                ForEach([1, 2, 4, 8, 16], id: \.self) { bars in
                    Button("\(bars) bar\(bars > 1 ? "s" : "")") { seq.loopBars = bars }
                }
            } label: {
                Text("\(seq.loopBars) BAR")
                    .font(Theme.mono(11, .bold))
                    .foregroundStyle(Theme.orange)
                    .metalInlayPill(tone: tone, hPad: 9, vPad: 8)
            }

            if seq.hasContent {
                Button { seq.clear() } label: {
                    InlaidMetalButton(system: "trash", lit: true, tint: Color(red: 0.55, green: 0.68, blue: 0.82), size: 36, tone: tone)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }

    private func iconToggle(_ system: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            InlaidMetalButton(system: system, lit: on, tint: Theme.orange, size: 36, tone: tone)
        }
        .buttonStyle(.plain)
    }
}
