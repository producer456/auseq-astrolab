import SwiftUI

/// Piano-roll strip for the selected track's clip — notes laid out by time (x)
/// and pitch (y) with a moving playhead. Read-only for now; the foundation for
/// note editing (M7).
struct ClipView: View {
    @ObservedObject var seq: Sequencer
    let trackID: UUID?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let loop = max(0.001, seq.loopLength)
            let rects = trackID.map { seq.noteRects(for: $0) } ?? []
            let pitches = rects.map { Int($0.note) }
            let lo = (pitches.min() ?? 48) - 1
            let hi = (pitches.max() ?? 72) + 1
            let span = max(1, hi - lo)
            let rowH = h / CGFloat(span)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8).fill(Theme.keybed.opacity(0.10))

                // Beat grid (downbeats brighter)
                ForEach(0..<max(1, seq.loopBars * seq.beatsPerBar), id: \.self) { b in
                    let x = CGFloat(Double(b) / Double(seq.loopBars * seq.beatsPerBar)) * w
                    Rectangle()
                        .fill(Theme.gold.opacity(b % seq.beatsPerBar == 0 ? 0.35 : 0.14))
                        .frame(width: b % seq.beatsPerBar == 0 ? 1 : 0.5, height: h)
                        .position(x: x, y: h / 2)
                }

                // Notes
                ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                    let x = CGFloat(r.start / loop) * w
                    let noteW = max(3, CGFloat((r.end - r.start) / loop) * w)
                    let y = h - CGFloat(Int(r.note) - lo) * rowH - rowH / 2
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.orange)
                        .frame(width: noteW, height: max(3, rowH - 1))
                        .position(x: x + noteW / 2, y: y)
                }

                // Playhead
                let px = CGFloat(min(loop, max(0, seq.positionSeconds)) / loop) * w
                Rectangle().fill(Theme.etched.opacity(0.8))
                    .frame(width: 1.5, height: h)
                    .position(x: px, y: h / 2)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.gold.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 96)
    }
}
