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

/// M6 transport + record/playback. Play runs a looping clock; with Record armed,
/// notes you play (keys or KeyLab) are captured onto the selected track's clip
/// and replayed each loop. Both the KeyLab transport and the on-screen bar drive it.
@MainActor
final class Sequencer: ObservableObject {
    struct NoteEvent {
        let time: Double      // seconds from loop start
        let note: UInt8
        let velocity: UInt8
        let isOn: Bool
    }

    @Published private(set) var isPlaying = false
    @Published private(set) var isRecordArmed = false
    @Published private(set) var isCountingIn = false
    @Published private(set) var positionSeconds = 0.0
    @Published private(set) var hasContent = false

    @Published var countInEnabled = true
    @Published var quantizeOn = false           // auto-quantize while recording
    @Published var quantizeGrid: QuantizeGrid = .d16
    @Published var loopEnabled = true   // off = linear: play to song end, then stop

    // User-placed loop region (in beats). end<=start ⇒ no region ⇒ loop the whole song.
    @Published var loopStartBeat = 0.0
    @Published var loopEndBeat = 0.0
    var hasLoopRegion: Bool { loopEndBeat > loopStartBeat + 1e-6 }
    var loopStartSec: Double { loopStartBeat * secondsPerBeat }
    var loopEndSec: Double { hasLoopRegion ? loopEndBeat * secondsPerBeat : loopLength }

    /// Snap a beat position to the current grid (reused as the edit/loop snap).
    func snapBeat(_ beat: Double) -> Double {
        let g = quantizeGrid.beats
        return (beat / g).rounded() * g
    }

    func setLoopRegion(startBeat: Double, endBeat: Double) {
        let total = Double(loopBars * beatsPerBar)
        let a = min(max(0, snapBeat(min(startBeat, endBeat))), total)
        let b = min(max(0, snapBeat(max(startBeat, endBeat))), total)
        loopStartBeat = a
        loopEndBeat = b
    }

    func clearLoopRegion() { loopStartBeat = 0; loopEndBeat = 0 }

    // MARK: - Section selection + clipboard editing

    @Published var selStartBeat = 0.0
    @Published var selEndBeat = 0.0
    @Published var selTrackID: UUID?         // the lane the selection was drawn on
    @Published var selectionAllTracks = false
    var hasSelection: Bool { selEndBeat > selStartBeat + 1e-6 }

    private struct ClipNote { let note: UInt8; let vel: UInt8; let offset: Double; let dur: Double }
    private var clipboard: [UUID: [ClipNote]] = [:]
    var hasClipboard: Bool { !clipboard.isEmpty }

    func setSelection(startBeat: Double, endBeat: Double, trackID: UUID?) {
        let total = Double(loopBars * beatsPerBar)
        selStartBeat = min(max(0, snapBeat(min(startBeat, endBeat))), total)
        selEndBeat = min(max(0, snapBeat(max(startBeat, endBeat))), total)
        selTrackID = trackID
    }

    func clearSelection() { selStartBeat = 0; selEndBeat = 0; selTrackID = nil }

    private func targetIDs(_ allTrackIDs: [UUID]) -> [UUID] {
        if selectionAllTracks { return allTrackIDs }
        if let t = selTrackID { return [t] }
        return []
    }

    func copySelection(allTrackIDs: [UUID]) {
        guard hasSelection else { return }
        let a = selStartBeat * secondsPerBeat, b = selEndBeat * secondsPerBeat
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
        let a = selStartBeat * secondsPerBeat, b = selEndBeat * secondsPerBeat
        for tid in targetIDs(allTrackIDs) { removeNotes(tid, from: a, to: b) }
        refreshContent()
        diag("seq", "erase \(selStartBeat)–\(selEndBeat) beats")
        objectWillChange.send()
    }

    /// Cut = ripple: copy the span, remove it, and slide everything after it back
    /// (closing the gap). Cutting across all tracks also shrinks the song length.
    func cutSelection(allTrackIDs: [UUID]) {
        guard hasSelection else { return }
        copySelection(allTrackIDs: allTrackIDs)
        let ids = targetIDs(allTrackIDs)
        let a = selStartBeat * secondsPerBeat
        let barLen = Double(beatsPerBar) * secondsPerBeat
        if selectionAllTracks {
            // All-tracks cut removes time from the song, so the note-shift and the
            // song-length shrink must use the SAME whole-bar span (else they desync).
            let removedBars = Int(((selEndBeat - selStartBeat) / Double(beatsPerBar)).rounded())
            if removedBars >= 1 {
                let b = a + Double(removedBars) * barLen
                for tid in ids { rippleRemove(tid, from: a, to: b) }
                loopBars = max(1, loopBars - removedBars)
            } else {
                let b = selEndBeat * secondsPerBeat   // sub-bar: just clear in place
                for tid in ids { removeNotes(tid, from: a, to: b) }
            }
        } else {
            let b = selEndBeat * secondsPerBeat        // one track ripples by the exact span
            for tid in ids { rippleRemove(tid, from: a, to: b) }
        }
        clearSelection()
        refreshContent()
        diag("seq", "cut (allTracks: \(selectionAllTracks))")
        objectWillChange.send()
    }

    private func rippleRemove(_ tid: UUID, from a: Double, to b: Double) {
        let span = b - a
        var out: [NoteEvent] = []
        for r in noteRects(for: tid) {
            if r.start >= a && r.start < b { continue }        // inside the cut → removed
            let shift = r.start >= b ? -span : 0               // after the cut → slide back
            out.append(NoteEvent(time: r.start + shift, note: r.note, velocity: r.vel, isOn: true))
            out.append(NoteEvent(time: r.end + shift, note: r.note, velocity: 0, isOn: false))
        }
        clips[tid] = out.sorted { $0.time < $1.time }
    }

    /// Paste the clipboard at the playhead. A single-track copy lands on the
    /// selected track; a multi-track copy keeps its original tracks.
    func pasteClipboard(selectedTrackID: UUID?) {
        guard hasClipboard else { return }
        let at = max(0, positionSeconds)
        let single = clipboard.count == 1 && !selectionAllTracks
        for (origID, notes) in clipboard {
            let tid = single ? (selectedTrackID ?? origID) : origID
            for n in notes {
                clips[tid, default: []].append(NoteEvent(time: at + n.offset, note: n.note, velocity: n.vel, isOn: true))
                clips[tid, default: []].append(NoteEvent(time: at + n.offset + n.dur, note: n.note, velocity: 0, isOn: false))
            }
            clips[tid]?.sort { $0.time < $1.time }
        }
        hasContent = true
        diag("seq", "paste at \(String(format: "%.2f", at))s")
        objectWillChange.send()
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

    private func refreshContent() {
        hasContent = clips.values.contains { !$0.isEmpty }
    }

    // Tempo grid
    @Published var bpm = 120.0 { didSet { bpm = min(300, max(20, bpm)) } }
    @Published var loopBars = 4
    @Published var metronomeOn = false { didSet { diag("seq", "metronome \(metronomeOn ? "ON" : "off")") } }
    let beatsPerBar = 4

    /// Playback emits notes through this (set by AppModel → AudioEngine).
    var onEvent: ((NoteEvent, UUID) -> Void)?
    /// Fires once per beat (downbeat = true on beat 1) — drives the metronome.
    var onBeat: ((Bool) -> Void)?
    /// Which track recording lands on (the selected track).
    var recordTrackID: (() -> UUID?)?

    /// Loop length is now a musical grid: bars × beats at the current tempo.
    var loopLength: Double { Double(loopBars * beatsPerBar) * 60.0 / bpm }
    private var secondsPerBeat: Double { 60.0 / bpm }

    private var clips: [UUID: [NoteEvent]] = [:]
    private var timer: Timer?
    private var anchor: Date?
    private var lastPos = 0.0
    private var lastBeat = -1
    private var active: [(note: UInt8, track: UUID)] = []   // sounding notes, for clean stop/loop
    private var quantizeDelta: [UInt8: Double] = [:]        // per-note start shift while recording quantized

    // MARK: - Transport

    func play() {
        guard !isPlaying else { return }
        // Start at the loop region if one is set; else honor count-in when armed.
        let startPos: Double
        if loopEnabled && hasLoopRegion {
            startPos = loopStartSec
        } else if isRecordArmed && countInEnabled {
            startPos = -Double(beatsPerBar) * secondsPerBeat
        } else {
            startPos = positionSeconds
        }
        isPlaying = true
        positionSeconds = startPos
        isCountingIn = startPos < 0
        anchor = Date().addingTimeInterval(-startPos)
        // Seed just below the start so an event at exactly position 0 still fires
        // (fireEvents uses an exclusive lower bound).
        lastPos = startPos == 0 ? -1e-6 : startPos
        lastBeat = Int.min
        diag("seq", "play (\(Int(bpm)) bpm, \(loopBars) bars, loop \(String(format: "%.1f", loopLength))s)")
        // .common run-loop modes so the clock keeps ticking during UI tracking
        // (scrolling, touches, sheet presentation) — otherwise the metronome and
        // playback stall whenever a finger is down.
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
        anchor = nil
        positionSeconds = 0; lastPos = 0
        quantizeDelta.removeAll()
        flushActive()
        diag("seq", "stop")
    }

    func toggleRecord() {
        isRecordArmed.toggle()
        diag("seq", "record \(isRecordArmed ? "ARMED" : "off")")
    }

    /// Move the playhead to a beat position (snapped). Paste/playback start here.
    func seek(toBeat beat: Double) {
        let total = Double(loopBars * beatsPerBar)
        let b = min(max(0, snapBeat(beat)), total)
        let sec = b * secondsPerBeat
        positionSeconds = sec
        lastPos = sec - 1e-6
        lastBeat = Int.min
        if isPlaying { anchor = Date().addingTimeInterval(-sec) }   // relocate playback too
    }

    func clear() {
        clips.removeAll()
        quantizeDelta.removeAll()
        hasContent = false
    }

    /// Snap an already-recorded track to the current grid (note starts move to
    /// the nearest grid line; each note keeps its length). No-op if empty.
    func quantize(_ trackID: UUID) {
        guard let events = clips[trackID], !events.isEmpty else { return }
        let g = quantizeGrid.beats * secondsPerBeat
        var open: [UInt8: (time: Double, vel: UInt8)] = [:]
        var out: [NoteEvent] = []
        for e in events.sorted(by: { $0.time < $1.time }) {
            if e.isOn {
                open[e.note] = (e.time, e.velocity)
            } else if let o = open[e.note] {
                let start = min(max(0, (o.time / g).rounded() * g), max(0, loopLength - 1e-3))
                let dur = max(g * 0.5, e.time - o.time)
                out.append(NoteEvent(time: start, note: e.note, velocity: o.vel, isOn: true))
                out.append(NoteEvent(time: start + dur, note: e.note, velocity: 0, isOn: false))
                open[e.note] = nil
            }
        }
        for (note, o) in open {                       // notes still held at clip end
            let start = min(max(0, (o.time / g).rounded() * g), max(0, loopLength - 1e-3))
            out.append(NoteEvent(time: start, note: note, velocity: o.vel, isOn: true))
            out.append(NoteEvent(time: start + g, note: note, velocity: 0, isOn: false))
        }
        clips[trackID] = out.sorted { $0.time < $1.time }
        objectWillChange.send()                       // clips isn't @Published; refresh views
        diag("seq", "quantized track to \(quantizeGrid.rawValue)")
    }

    /// Paired note rectangles (start/end seconds + pitch) for drawing a track's
    /// clip in the piano-roll. Notes still held at the loop end are clamped.
    func noteRects(for trackID: UUID) -> [(start: Double, end: Double, note: UInt8, vel: UInt8)] {
        guard let events = clips[trackID] else { return [] }
        var open: [UInt8: (time: Double, vel: UInt8)] = [:]
        var rects: [(start: Double, end: Double, note: UInt8, vel: UInt8)] = []
        for e in events.sorted(by: { $0.time < $1.time }) {
            if e.isOn {
                open[e.note] = (e.time, e.velocity)
            } else if let o = open[e.note] {
                rects.append((start: o.time, end: e.time, note: e.note, vel: o.vel))
                open[e.note] = nil
            }
        }
        for (note, o) in open { rects.append((start: o.time, end: loopLength, note: note, vel: o.vel)) }
        return rects
    }

    // MARK: - Recording (called from AppModel's live-input path)

    func recordNoteOn(_ note: UInt8, velocity: UInt8) {
        guard isPlaying, isRecordArmed, positionSeconds >= 0, let tid = recordTrackID?() else { return }
        var time = positionSeconds
        if quantizeOn {
            let grid = quantizeGrid.beats * secondsPerBeat
            let snapped = (time / grid).rounded() * grid
            quantizeDelta[note] = snapped - time      // remember the shift...
            time = snapped
        }
        clips[tid, default: []].append(NoteEvent(time: time, note: note, velocity: velocity, isOn: true))
        hasContent = true
    }

    func recordNoteOff(_ note: UInt8) {
        guard isPlaying, isRecordArmed, positionSeconds >= 0, let tid = recordTrackID?() else {
            quantizeDelta[note] = nil
            return
        }
        var time = positionSeconds
        if quantizeOn, let delta = quantizeDelta[note] {
            time += delta                              // ...so the end moves with the start (length preserved)
        }
        quantizeDelta[note] = nil
        clips[tid, default: []].append(NoteEvent(time: time, note: note, velocity: 0, isOn: false))
    }

    // MARK: - Playback clock

    private func tick() {
        guard isPlaying, let anchor else { return }
        var pos = Date().timeIntervalSince(anchor)
        // Record as long as needed: grow the song to fit while recording — but
        // NOT when looping a region (that's an overdub: keep it bounded to the
        // region instead of silently extending/truncating the take).
        if isRecordArmed && pos > 0 && !(loopEnabled && hasLoopRegion) {
            let barLen = Double(beatsPerBar) * secondsPerBeat
            let needed = Int(ceil((pos + 0.0001) / barLen))
            if needed > loopBars { loopBars = needed }
        }
        // Wrap point: the loop region's end if set, else the song end.
        let regionLoop = loopEnabled && hasLoopRegion
        let end = regionLoop ? loopEndSec : loopLength
        if pos >= end {
            fireEvents(from: lastPos, to: end)
            flushActive()                       // no hung notes across the seam
            if loopEnabled {
                let start = regionLoop ? loopStartSec : 0
                let remainder = pos - end
                self.anchor = Date().addingTimeInterval(-(start + remainder))
                lastPos = start - 1e-6          // include an event exactly at the loop start
                pos = start + remainder
                fireEvents(from: lastPos, to: pos)
            } else {
                diag("seq", "reached song end → stop")
                stop()                          // linear: stop at the end
                return
            }
        } else {
            fireEvents(from: lastPos, to: pos)
        }
        lastPos = pos
        positionSeconds = pos
        if isCountingIn && pos >= 0 { isCountingIn = false }

        // Metronome: fire once when the beat index changes.
        let beat = Int(floor(pos / secondsPerBeat))
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

    /// "bar.beat" (1-based), or "IN n" during the count-in.
    var positionLabel: String {
        if positionSeconds < 0 {
            return "IN \(Int(ceil(-positionSeconds / secondsPerBeat)))"
        }
        let beat = Int(floor(positionSeconds / secondsPerBeat))
        return "\(beat / beatsPerBar + 1).\(beat % beatsPerBar + 1)"
    }

    /// Current beat within the bar (0-based) — for the beat dots.
    var beatInBar: Int {
        let beat = Int(floor(positionSeconds / secondsPerBeat))
        return ((beat % beatsPerBar) + beatsPerBar) % beatsPerBar
    }
}
