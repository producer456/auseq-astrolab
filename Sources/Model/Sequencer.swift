import Foundation
import Combine

/// Quantize grid (note value). `beats` = length in quarter-note beats.
enum QuantizeGrid: String, CaseIterable, Identifiable {
    case bar = "Bar", d2 = "1/2", d4 = "1/4", d8 = "1/8", d16 = "1/16", d32 = "1/32", d8t = "1/8T", d16t = "1/16T"
    var id: String { rawValue }
    var beats: Double {
        switch self {
        case .bar: return 4.0      // one bar in 4/4
        case .d2: return 2.0
        case .d4: return 1.0
        case .d8: return 0.5
        case .d16: return 0.25
        case .d32: return 0.125
        case .d8t: return 1.0 / 3.0
        case .d16t: return 1.0 / 6.0
        }
    }
}

/// Transport + record/playback engine. **Beat-native** (v2.1): all musical time
/// is in beats, so it's tempo-independent and persistence-ready; the wall clock
/// only samples elapsed time and re-bases on tempo changes so playback never
/// drifts. Seconds are exposed at the boundary for any callers that want them.
@MainActor
final class Sequencer: ObservableObject {
    struct NoteEvent {
        let time: Double      // BEATS from song start
        let note: UInt8
        let velocity: UInt8
        let isOn: Bool
    }

    @Published private(set) var isPlaying = false
    @Published private(set) var isRecordArmed = false
    @Published private(set) var isCountingIn = false
    @Published private(set) var positionBeats = 0.0
    @Published private(set) var hasContent = false

    @Published var countInEnabled = true
    @Published var quantizeOn = false
    @Published var quantizeGrid: QuantizeGrid = .d16
    @Published var loopEnabled = true

    // Tempo / grid
    @Published var bpm = 120.0 {
        didSet {
            bpm = min(300, max(20, bpm))
            if isPlaying { anchorBeat = positionBeats; anchorDate = Date() }   // re-base so tempo change doesn't jump
        }
    }
    @Published var loopBars = 4
    @Published var metronomeOn = false { didSet { diag("seq", "metronome \(metronomeOn ? "ON" : "off")") } }
    let beatsPerBar = 4

    // Derived units
    var secondsPerBeat: Double { 60.0 / bpm }
    var totalBeats: Double { Double(loopBars * beatsPerBar) }
    var positionSeconds: Double { positionBeats * secondsPerBeat }   // boundary convenience
    var loopLength: Double { totalBeats * secondsPerBeat }

    // User-placed loop region (beats). end<=start ⇒ no region ⇒ loop whole song.
    @Published var loopStartBeat = 0.0
    @Published var loopEndBeat = 0.0
    var hasLoopRegion: Bool { loopEndBeat > loopStartBeat + 1e-6 }

    // Selection (beats)
    @Published var selStartBeat = 0.0
    @Published var selEndBeat = 0.0
    @Published var selTrackID: UUID?
    @Published var selectionAllTracks = false
    var hasSelection: Bool { selEndBeat > selStartBeat + 1e-6 }

    // Callbacks (set by AppModel)
    var onEvent: ((NoteEvent, UUID) -> Void)?
    var onBeat: ((Bool) -> Void)?
    var recordTrackID: (() -> UUID?)?

    private var clips: [UUID: [NoteEvent]] = [:]
    private var timer: Timer?
    private var anchorDate: Date?
    private var anchorBeat = 0.0
    private var lastPos = 0.0          // beats
    private var lastBeat = -1
    private var active: [(note: UInt8, track: UUID)] = []
    private var quantizeDelta: [UInt8: Double] = [:]   // per-note start shift (beats) while recording quantized

    private struct ClipNote { let note: UInt8; let vel: UInt8; let offset: Double; let dur: Double }   // beats
    private var clipboard: [UUID: [ClipNote]] = [:]
    var hasClipboard: Bool { !clipboard.isEmpty }

    // MARK: - Snap / loop region / selection

    func snapBeat(_ beat: Double) -> Double {
        let g = quantizeGrid.beats
        return (beat / g).rounded() * g
    }

    func setLoopRegion(startBeat: Double, endBeat: Double) {
        loopStartBeat = min(max(0, snapBeat(min(startBeat, endBeat))), totalBeats)
        loopEndBeat = min(max(0, snapBeat(max(startBeat, endBeat))), totalBeats)
    }
    func clearLoopRegion() { loopStartBeat = 0; loopEndBeat = 0 }

    func setSelection(startBeat: Double, endBeat: Double, trackID: UUID?) {
        selStartBeat = min(max(0, snapBeat(min(startBeat, endBeat))), totalBeats)
        selEndBeat = min(max(0, snapBeat(max(startBeat, endBeat))), totalBeats)
        selTrackID = trackID
    }
    func clearSelection() { selStartBeat = 0; selEndBeat = 0; selTrackID = nil }

    private func targetIDs(_ allTrackIDs: [UUID]) -> [UUID] {
        if selectionAllTracks { return allTrackIDs }
        if let t = selTrackID { return [t] }
        return []
    }

    // MARK: - Clipboard editing (all beats)

    func copySelection(allTrackIDs: [UUID]) {
        guard hasSelection else { return }
        let a = selStartBeat, b = selEndBeat
        clipboard.removeAll()
        for tid in targetIDs(allTrackIDs) {
            let notes = noteRects(for: tid).filter { $0.start >= a && $0.start < b }
                .map { ClipNote(note: $0.note, vel: $0.vel, offset: $0.start - a, dur: $0.end - $0.start) }
            if !notes.isEmpty { clipboard[tid] = notes }
        }
        diag("seq", "copy \(clipboard.values.reduce(0) { $0 + $1.count }) notes")
        objectWillChange.send()
    }

    func eraseSelection(allTrackIDs: [UUID]) {
        guard hasSelection else { return }
        for tid in targetIDs(allTrackIDs) { removeNotes(tid, from: selStartBeat, to: selEndBeat) }
        refreshContent(); objectWillChange.send()
    }

    func cutSelection(allTrackIDs: [UUID]) {
        guard hasSelection else { return }
        copySelection(allTrackIDs: allTrackIDs)
        let ids = targetIDs(allTrackIDs)
        let a = selStartBeat
        if selectionAllTracks {
            let removedBars = Int(((selEndBeat - selStartBeat) / Double(beatsPerBar)).rounded())
            if removedBars >= 1 {
                let b = a + Double(removedBars * beatsPerBar)
                for tid in ids { rippleRemove(tid, from: a, to: b) }
                loopBars = max(1, loopBars - removedBars)
            } else {
                for tid in ids { removeNotes(tid, from: a, to: selEndBeat) }
            }
        } else {
            for tid in ids { rippleRemove(tid, from: a, to: selEndBeat) }
        }
        clearSelection(); refreshContent(); objectWillChange.send()
    }

    private func rippleRemove(_ tid: UUID, from a: Double, to b: Double) {
        let span = b - a
        var out: [NoteEvent] = []
        for r in noteRects(for: tid) {
            if r.start >= a && r.start < b { continue }
            let shift = r.start >= b ? -span : 0
            out.append(NoteEvent(time: r.start + shift, note: r.note, velocity: r.vel, isOn: true))
            out.append(NoteEvent(time: r.end + shift, note: r.note, velocity: 0, isOn: false))
        }
        clips[tid] = out.sorted { $0.time < $1.time }
    }

    func pasteClipboard(selectedTrackID: UUID?) {
        guard hasClipboard else { return }
        let at = max(0, positionBeats)
        let single = clipboard.count == 1 && !selectionAllTracks
        for (origID, notes) in clipboard {
            let tid = single ? (selectedTrackID ?? origID) : origID
            for n in notes {
                clips[tid, default: []].append(NoteEvent(time: at + n.offset, note: n.note, velocity: n.vel, isOn: true))
                clips[tid, default: []].append(NoteEvent(time: at + n.offset + n.dur, note: n.note, velocity: 0, isOn: false))
            }
            clips[tid]?.sort { $0.time < $1.time }
        }
        hasContent = true; objectWillChange.send()
    }

    private func removeNotes(_ tid: UUID, from a: Double, to b: Double) {
        let kept = noteRects(for: tid).filter { !($0.start >= a && $0.start < b) }
        var out: [NoteEvent] = []
        for r in kept {
            out.append(NoteEvent(time: r.start, note: r.note, velocity: r.vel, isOn: true))
            out.append(NoteEvent(time: r.end, note: r.note, velocity: 0, isOn: false))
        }
        clips[tid] = out.sorted { $0.time < $1.time }
    }

    private func refreshContent() { hasContent = clips.values.contains { !$0.isEmpty } }

    // MARK: - Transport

    func play() {
        guard !isPlaying else { return }
        let startBeat: Double
        if loopEnabled && hasLoopRegion {
            startBeat = loopStartBeat
        } else if isRecordArmed && countInEnabled {
            startBeat = -Double(beatsPerBar)
        } else {
            startBeat = positionBeats
        }
        isPlaying = true
        positionBeats = startBeat
        isCountingIn = startBeat < 0
        anchorBeat = startBeat
        anchorDate = Date()
        lastPos = startBeat == 0 ? -1e-6 : startBeat
        lastBeat = Int.min
        diag("seq", "play (\(Int(bpm)) bpm, \(loopBars) bars)")
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        isPlaying = false
        isRecordArmed = false
        timer?.invalidate(); timer = nil
        anchorDate = nil
        positionBeats = 0; lastPos = 0
        quantizeDelta.removeAll()
        flushActive()
        diag("seq", "stop")
    }

    func toggleRecord() {
        isRecordArmed.toggle()
        diag("seq", "record \(isRecordArmed ? "ARMED" : "off")")
    }

    func seek(toBeat beat: Double) {
        let b = min(max(0, snapBeat(beat)), totalBeats)
        positionBeats = b
        lastPos = b - 1e-6
        lastBeat = Int.min
        if isPlaying { anchorBeat = b; anchorDate = Date() }
    }

    func clear() {
        clips.removeAll(); quantizeDelta.removeAll(); hasContent = false
    }

    // MARK: - Persistence support

    /// Raw recorded events for a track (beats) — used when saving a song.
    func clipNotes(for trackID: UUID) -> [NoteEvent] { clips[trackID] ?? [] }

    /// Replace a track's clip wholesale (used when loading a song).
    func loadClip(_ events: [NoteEvent], for trackID: UUID) {
        clips[trackID] = events.sorted { $0.time < $1.time }
        refreshContent()
        objectWillChange.send()
    }

    // MARK: - Quantize already-recorded

    func quantize(_ trackID: UUID) {
        guard let events = clips[trackID], !events.isEmpty else { return }
        let g = quantizeGrid.beats
        var open: [UInt8: (time: Double, vel: UInt8)] = [:]
        var out: [NoteEvent] = []
        func snapStart(_ t: Double) -> Double { min(max(0, (t / g).rounded() * g), max(0, totalBeats - 1e-3)) }
        for e in events.sorted(by: { $0.time < $1.time }) {
            if e.isOn { open[e.note] = (e.time, e.velocity) }
            else if let o = open[e.note] {
                let start = snapStart(o.time)
                let dur = max(g * 0.5, e.time - o.time)
                out.append(NoteEvent(time: start, note: e.note, velocity: o.vel, isOn: true))
                out.append(NoteEvent(time: start + dur, note: e.note, velocity: 0, isOn: false))
                open[e.note] = nil
            }
        }
        for (note, o) in open {
            let start = snapStart(o.time)
            out.append(NoteEvent(time: start, note: note, velocity: o.vel, isOn: true))
            out.append(NoteEvent(time: start + g, note: note, velocity: 0, isOn: false))
        }
        clips[trackID] = out.sorted { $0.time < $1.time }
        objectWillChange.send()
        diag("seq", "quantized track to \(quantizeGrid.rawValue)")
    }

    /// Paired note rectangles in BEATS (start/end/pitch/vel) for drawing + editing.
    func noteRects(for trackID: UUID) -> [(start: Double, end: Double, note: UInt8, vel: UInt8)] {
        guard let events = clips[trackID] else { return [] }
        var open: [UInt8: (time: Double, vel: UInt8)] = [:]
        var rects: [(start: Double, end: Double, note: UInt8, vel: UInt8)] = []
        for e in events.sorted(by: { $0.time < $1.time }) {
            if e.isOn { open[e.note] = (e.time, e.velocity) }
            else if let o = open[e.note] {
                rects.append((start: o.time, end: e.time, note: e.note, vel: o.vel))
                open[e.note] = nil
            }
        }
        for (note, o) in open { rects.append((start: o.time, end: totalBeats, note: note, vel: o.vel)) }
        return rects
    }

    // MARK: - Recording (beats)

    func recordNoteOn(_ note: UInt8, velocity: UInt8) {
        guard isPlaying, isRecordArmed, positionBeats >= 0, let tid = recordTrackID?() else { return }
        var time = positionBeats
        if quantizeOn {
            let snapped = snapBeat(time)
            quantizeDelta[note] = snapped - time
            time = snapped
        }
        clips[tid, default: []].append(NoteEvent(time: time, note: note, velocity: velocity, isOn: true))
        hasContent = true
    }

    func recordNoteOff(_ note: UInt8) {
        guard isPlaying, isRecordArmed, positionBeats >= 0, let tid = recordTrackID?() else {
            quantizeDelta[note] = nil; return
        }
        var time = positionBeats
        if quantizeOn, let delta = quantizeDelta[note] { time += delta }
        quantizeDelta[note] = nil
        clips[tid, default: []].append(NoteEvent(time: time, note: note, velocity: 0, isOn: false))
    }

    // MARK: - Playback clock (beats)

    private func tick() {
        guard isPlaying, let anchorDate else { return }
        var pos = anchorBeat + Date().timeIntervalSince(anchorDate) / secondsPerBeat
        // Grow song to fit a take (not while looping a region — that's overdub).
        if isRecordArmed && pos > 0 && !(loopEnabled && hasLoopRegion) {
            let needed = Int(ceil((pos + 0.001) / Double(beatsPerBar)))
            if needed > loopBars { loopBars = needed }
        }
        let regionLoop = loopEnabled && hasLoopRegion
        let end = regionLoop ? loopEndBeat : totalBeats
        if pos >= end {
            fireEvents(from: lastPos, to: end)
            flushActive()
            if loopEnabled {
                let start = regionLoop ? loopStartBeat : 0
                let remainder = pos - end
                anchorBeat = start; self.anchorDate = Date().addingTimeInterval(-remainder * secondsPerBeat)
                lastPos = start - 1e-6
                pos = start + remainder
                fireEvents(from: lastPos, to: pos)
            } else {
                diag("seq", "reached song end → stop")
                stop(); return
            }
        } else {
            fireEvents(from: lastPos, to: pos)
        }
        lastPos = pos
        positionBeats = pos
        if isCountingIn && pos >= 0 { isCountingIn = false }

        let beat = Int(floor(pos))
        if beat != lastBeat {
            lastBeat = beat
            onBeat?(((beat % beatsPerBar) + beatsPerBar) % beatsPerBar == 0)
        }
    }

    private func fireEvents(from a: Double, to b: Double) {
        guard onEvent != nil else { return }
        for (tid, events) in clips {
            for e in events where e.time > a && e.time <= b {
                onEvent?(e, tid)
                if e.isOn { active.append((e.note, tid)) }
                else { active.removeAll { $0.note == e.note && $0.track == tid } }
            }
        }
    }

    private func flushActive() {
        for a in active { onEvent?(NoteEvent(time: 0, note: a.note, velocity: 0, isOn: false), a.track) }
        active.removeAll()
    }

    // MARK: - Readout

    var positionLabel: String {
        if positionBeats < 0 { return "IN \(Int(ceil(-positionBeats)))" }
        let beat = Int(floor(positionBeats))
        return "\(beat / beatsPerBar + 1).\(beat % beatsPerBar + 1)"
    }

    var beatInBar: Int {
        let beat = Int(floor(positionBeats))
        return ((beat % beatsPerBar) + beatsPerBar) % beatsPerBar
    }
}
