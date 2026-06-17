import SwiftUI

/// Transport strip (M6) — driven by both the KeyLab's transport buttons and
/// these on-screen controls. Shows Stop / Play / Record and the position clock.
struct TransportBar: View {
    @ObservedObject var seq: Sequencer
    var onQuantizeSelected: () -> Void = {}
    var onQuantizeAll: () -> Void = {}
    var compact: Bool = false

    var body: some View {
        if compact {
            ScrollView(.horizontal, showsIndicators: false) { controls }
                .background(Theme.rail)
        } else {
            controls.background(Theme.rail)
        }
    }

    private var controls: some View {
        HStack(spacing: compact ? 12 : 16) {
            // Stop
            transportButton(system: "stop.fill", active: false, tint: Theme.etched) {
                seq.stop()
            }
            // Play
            transportButton(system: "play.fill", active: seq.isPlaying, tint: Theme.orange) {
                seq.play()
            }
            // Record (arm)
            transportButton(system: "record.circle", active: seq.isRecordArmed, tint: .red) {
                seq.toggleRecord()
            }

            Text(seq.positionLabel)
                .font(Theme.mono(18, .bold))
                .foregroundStyle(Theme.etched)
                .monospacedDigit()
                .frame(width: 54, alignment: .leading)
                .padding(.leading, 4)

            // Beat dots
            HStack(spacing: 4) {
                ForEach(0..<seq.beatsPerBar, id: \.self) { i in
                    Circle()
                        .fill(seq.isPlaying && i == seq.beatInBar
                              ? (i == 0 ? Theme.orange : Theme.etched)
                              : Theme.gold.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }

            if !compact { Spacer() }

            // Loop on/off (off = linear play-through)
            Button { seq.loopEnabled.toggle() } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(seq.loopEnabled ? Theme.orange : Theme.etchedSoft)
            }
            // Metronome
            Button { seq.metronomeOn.toggle() } label: {
                Image(systemName: "metronome")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(seq.metronomeOn ? Theme.orange : Theme.etchedSoft)
            }
            // Count-in
            Button { seq.countInEnabled.toggle() } label: {
                Image(systemName: "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(seq.countInEnabled ? Theme.orange : Theme.etchedSoft)
            }
            // Quantize: grid + auto-on-record + apply to recorded notes
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
                    .foregroundStyle(seq.quantizeOn ? Theme.orange : Theme.etchedSoft)
            }

            // Tempo
            HStack(spacing: 6) {
                Button { seq.bpm = max(40, seq.bpm - 1) } label: { Image(systemName: "minus") }
                Text("\(Int(seq.bpm))").font(Theme.mono(13, .bold)).foregroundStyle(Theme.etched)
                    .frame(width: 30)
                Button { seq.bpm = min(240, seq.bpm + 1) } label: { Image(systemName: "plus") }
                Text("BPM").etchedLabel(8, soft: true, weight: .medium)
            }
            .foregroundStyle(Theme.orange)

            // Loop length (bars)
            Menu {
                ForEach([1, 2, 4, 8, 16], id: \.self) { bars in
                    Button("\(bars) bar\(bars > 1 ? "s" : "")") { seq.loopBars = bars }
                }
            } label: {
                Text("\(seq.loopBars) BAR").etchedLabel(10, weight: .semibold).foregroundStyle(Theme.orange)
            }

            if seq.hasContent {
                Button { seq.clear() } label: {
                    Image(systemName: "trash").foregroundStyle(Theme.etchedSoft)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func transportButton(system: String, active: Bool, tint: Color,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(active ? tint : Theme.etchedSoft)
                .frame(width: 40, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(active ? tint.opacity(0.18) : Color.white.opacity(0.5))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .black.opacity(0.05)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(active ? tint : Theme.gold.opacity(0.4), lineWidth: active ? 1.5 : 1)
                )
                .shadow(color: active ? tint.opacity(0.55) : .clear, radius: 6)   // backlit glow
        }
        .buttonStyle(.plain)
    }
}
