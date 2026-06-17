import SwiftUI
import UIKit

/// Multi-touch piano. Touch handling is done in a UIKit view
/// (`isMultipleTouchEnabled` + touchesBegan/Moved/Ended) bridged into SwiftUI,
/// which is the reliable way to get true per-finger multitouch. SwiftUI only
/// draws the keys; the transparent overlay reports note on/off and which notes
/// are held (for highlighting). Sliding a finger across keys = glissando.
struct PianoKeyboardView: View {
    @ObservedObject var model: AppModel
    var startNote: Int = 48      // C3
    var octaves: Int = 2
    var height: CGFloat = 200

    @State private var pressed: Set<UInt8> = []

    var body: some View {
        VStack(spacing: 4) {
            ledStrip.frame(height: 12)
            keysView
        }
        .frame(height: height)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.keybed)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
        )
    }

    /// AstroLab per-key LED dots — light blue when a note plays.
    private var ledStrip: some View {
        GeometryReader { geo in
            let layout = KeyboardLayout(size: CGSize(width: geo.size.width, height: 100),
                                        startNote: startNote, octaves: octaves)
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.whites.enumerated()), id: \.offset) { idx, n in
                    let lit = pressed.contains(UInt8(n))
                    Circle()
                        .fill(lit ? Theme.orange : Color.black.opacity(0.13))
                        .frame(width: 5, height: 5)
                        .shadow(color: lit ? Theme.orange.opacity(0.9) : .clear, radius: lit ? 5 : 0)
                        .offset(x: CGFloat(idx) * layout.stride + layout.w / 2 - 2.5, y: 3)
                }
            }
        }
    }

    private var keysView: some View {
        GeometryReader { geo in
            let layout = KeyboardLayout(size: geo.size, startNote: startNote, octaves: octaves)
            ZStack(alignment: .topLeading) {
                ForEach(Array(layout.whites.enumerated()), id: \.offset) { idx, n in
                    key(isBlack: false, pressed: pressed.contains(UInt8(n)))
                        .frame(width: layout.w, height: layout.h)
                        .offset(x: CGFloat(idx) * layout.stride, y: 0)
                }
                ForEach(layout.blacks, id: \.note) { b in
                    key(isBlack: true, pressed: pressed.contains(UInt8(b.note)))
                        .frame(width: layout.blackW, height: layout.blackH)
                        .offset(x: b.x, y: 0)
                }
                MultiTouchPiano(
                    startNote: startNote,
                    octaves: octaves,
                    onNoteOn: { note in
                        model.playNoteOn(note, velocity: 100)
                        pressed.insert(note)
                    },
                    onNoteOff: { note in
                        model.playNoteOff(note)
                        pressed.remove(note)
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private func key(isBlack: Bool, pressed: Bool) -> some View {
        let fill: Color = isBlack
            ? (pressed ? Theme.orange : Theme.blackKey)
            : (pressed ? Theme.orange : Theme.ivory)
        return RoundedRectangle(cornerRadius: 5)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - UIKit multitouch bridge

private struct MultiTouchPiano: UIViewRepresentable {
    let startNote: Int
    let octaves: Int
    let onNoteOn: (UInt8) -> Void
    let onNoteOff: (UInt8) -> Void

    func makeUIView(context: Context) -> PianoTouchView {
        let v = PianoTouchView()
        v.startNote = startNote
        v.octaves = octaves
        v.onNoteOn = onNoteOn
        v.onNoteOff = onNoteOff
        return v
    }

    func updateUIView(_ v: PianoTouchView, context: Context) {
        v.startNote = startNote
        v.octaves = octaves
        v.onNoteOn = onNoteOn
        v.onNoteOff = onNoteOff
    }
}

private final class PianoTouchView: UIView {
    var startNote: Int = 48
    var octaves: Int = 2
    var onNoteOn: ((UInt8) -> Void)?
    var onNoteOff: ((UInt8) -> Void)?

    private var touchNotes: [UITouch: UInt8] = [:]
    private var noteCounts: [UInt8: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var layout: KeyboardLayout {
        KeyboardLayout(size: bounds.size, startNote: startNote, octaves: octaves)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let l = layout
        for t in touches { assign(t, to: l.noteAt(t.location(in: self))) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let l = layout
        for t in touches { assign(t, to: l.noteAt(t.location(in: self))) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { assign(t, to: nil) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { assign(t, to: nil) }
    }

    private func assign(_ touch: UITouch, to newNote: UInt8?) {
        let old = touchNotes[touch]
        if old == newNote { return }
        if let old { release(old) }
        if let newNote {
            touchNotes[touch] = newNote
            press(newNote)
        } else {
            touchNotes[touch] = nil
        }
    }

    private func press(_ note: UInt8) {
        noteCounts[note, default: 0] += 1
        if noteCounts[note] == 1 { onNoteOn?(note) }
    }

    private func release(_ note: UInt8) {
        guard let c = noteCounts[note] else { return }
        if c <= 1 {
            noteCounts[note] = nil
            onNoteOff?(note)
        } else {
            noteCounts[note] = c - 1
        }
    }
}

// MARK: - Geometry + hit-testing

/// Geometry + hit-testing for the keyboard, computed from the available size.
private struct KeyboardLayout {
    let whites: [Int]
    let w, h, blackW, blackH, stride: CGFloat
    let blacks: [(note: Int, x: CGFloat)]

    private static let whiteSemis = [0, 2, 4, 5, 7, 9, 11]
    private static let blackBeforePC: Set<Int> = [0, 2, 5, 7, 9]

    init(size: CGSize, startNote: Int, octaves: Int) {
        var notes: [Int] = []
        for o in 0..<octaves {
            for s in Self.whiteSemis { notes.append(startNote + o * 12 + s) }
        }
        notes.append(startNote + octaves * 12)
        whites = notes

        let spacing: CGFloat = 1
        w = (size.width - spacing * CGFloat(notes.count - 1)) / CGFloat(notes.count)
        h = size.height
        blackW = w * 0.62
        blackH = h * 0.6
        stride = w + spacing

        let bw = blackW, st = stride, ww = w
        blacks = notes.enumerated().compactMap { idx, n in
            guard idx < notes.count - 1,
                  Self.blackBeforePC.contains(((n % 12) + 12) % 12) else { return nil }
            let centerX = CGFloat(idx) * st + ww + spacing / 2
            return (n + 1, centerX - bw / 2)
        }
    }

    func noteAt(_ p: CGPoint) -> UInt8? {
        if p.y <= blackH {
            for b in blacks where p.x >= b.x && p.x <= b.x + blackW {
                return UInt8(b.note)
            }
        }
        let idx = max(0, min(whites.count - 1, Int(p.x / stride)))
        return UInt8(whites[idx])
    }
}
