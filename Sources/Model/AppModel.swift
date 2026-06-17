import Foundation
import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox

/// Top-level app state: tracks, selection, and the live wiring between the
/// MIDI input, the on-screen keyboard, and the audio host.
@MainActor
final class AppModel: ObservableObject {

    @Published var tracks: [Track] = []
    @Published var selectedTrackID: UUID? { didSet { updateSelectLEDs() } }

    let audio = AudioEngine()
    let midi = MIDIManager()
    let browser = AUComponentBrowser()
    let sequencer = Sequencer()

    private let palette: [Color] = [.blue, .pink, .green, .orange, .purple, .teal, .yellow, .red]

    init() {
        addTrack()
        audio.start()
        browser.refresh()

        midi.onMessage = { [weak self] message, source in
            self?.handleIncoming(message, from: source)
        }
        midi.start()
        updateSelectLEDs()   // output port exists now; reflect the initial selection

        // Sequencer playback → instrument; recording lands on the selected track.
        sequencer.recordTrackID = { [weak self] in
            guard let self else { return nil }
            return self.tracks.first { $0.armed }?.id ?? self.selectedTrackID
        }
        sequencer.onBeat = { [weak self] downbeat in
            guard let self else { return }
            // Always click during the count-in, even if the metronome is off.
            if self.sequencer.metronomeOn || self.sequencer.isCountingIn {
                self.audio.click(downbeat: downbeat)
            }
        }
        sequencer.onEvent = { [weak self] event, trackID in
            guard let self else { return }
            let channel = self.tracks.first { $0.id == trackID }?.midiChannel ?? 0
            if event.isOn {
                self.audio.noteOn(event.note, velocity: event.velocity, channel: channel, to: trackID)
            } else {
                self.audio.noteOff(event.note, channel: channel, to: trackID)
            }
        }
    }

    var selectedTrack: Track? {
        tracks.first { $0.id == selectedTrackID }
    }

    /// The hosted AUAudioUnit for the selected track, if it has one loaded.
    var selectedAU: AUAudioUnit? {
        guard let track = selectedTrack else { return nil }
        return audio.auAudioUnit(for: track.id)
    }

    // MARK: - Track management

    @discardableResult
    func addTrack() -> Track {
        let color = palette[tracks.count % palette.count]
        let track = Track(name: "Track \(tracks.count + 1)", color: color)
        tracks.append(track)
        selectedTrackID = track.id
        setArmed(track)        // new track is selected → auto-armed
        return track
    }

    func removeTrack(_ track: Track) {
        audio.removeTrack(track.id)
        tracks.removeAll { $0.id == track.id }
        if selectedTrackID == track.id { selectedTrackID = tracks.first?.id }
    }

    func select(_ track: Track) {
        selectedTrackID = track.id
        paramBank = 0
        setArmed(track)        // selected track auto-arms (single-arm)
        syncBrowseToSelection() // point the big wheel at this track's instrument
    }

    private func setArmed(_ track: Track) {
        for t in tracks { t.armed = (t.id == track.id) }
    }

    func quantizeSelected() {
        if let id = selectedTrackID { sequencer.quantize(id) }
    }

    func quantizeAll() {
        for t in tracks { sequencer.quantize(t.id) }
    }

    // MARK: - Arranger edits (operate on the current selection)

    func editCut()   { sequencer.cutSelection(allTrackIDs: tracks.map { $0.id }) }
    func editCopy()  { sequencer.copySelection(allTrackIDs: tracks.map { $0.id }) }
    func editErase() { sequencer.eraseSelection(allTrackIDs: tracks.map { $0.id }) }
    func editPaste() { sequencer.pasteClipboard(selectedTrackID: selectedTrackID) }

    // MARK: - Encoder bank paging (9 encoders → a page of 9 params)

    static let encoderCount = 9
    /// Which page of parameters the KeyLab encoders currently drive.
    @Published var paramBank = 0

    var paramCount: Int { selectedAU?.parameterTree?.allParameters.count ?? 0 }
    var bankCount: Int { max(1, Int(ceil(Double(paramCount) / Double(Self.encoderCount)))) }

    func pageBank(_ delta: Int) {
        paramBank = max(0, min(bankCount - 1, paramBank + delta))
    }

    // MARK: - Presets (relocated onto the wood deck)

    var presets: [AUAudioUnitPreset] { selectedAU?.factoryPresets ?? [] }
    var currentPresetName: String { selectedAU?.currentPreset?.name ?? "Init" }

    func applyPreset(_ preset: AUAudioUnitPreset) {
        selectedAU?.currentPreset = preset
        paramBank = 0
        objectWillChange.send()
    }

    // MARK: - Sound browse (the big wheel — driven on-screen and by the KeyLab jog)

    /// Index into the instrument list the big wheel is currently showing.
    @Published var browseIndex = 0

    /// Point the wheel at the selected track's loaded instrument (called on track
    /// change / after a load), so turning the jog browses from there.
    func syncBrowseToSelection() {
        if let name = selectedTrack?.instrumentName,
           let i = browser.instruments.firstIndex(where: { $0.name == name }) {
            browseIndex = i
        }
    }

    /// Step the wheel through the instrument list (KeyLab jog turn).
    func browseStep(_ delta: Int) {
        let n = browser.instruments.count
        guard n > 0, delta != 0 else { return }
        browseIndex = ((browseIndex + delta) % n + n) % n
    }

    /// Load the currently-browsed instrument onto the selected track (jog press).
    func browseCommit() {
        guard let track = selectedTrack, browser.instruments.indices.contains(browseIndex) else { return }
        assignInstrument(browser.instruments[browseIndex], to: track)
    }

    func assignInstrument(_ component: AVAudioUnitComponent, to track: Track) {
        diag("app", "load '\(component.name)' → \(track.name)")
        audio.loadInstrument(component, for: track.id) { [weak self] name in
            track.instrumentName = name
            track.hasInstrument = true
            self?.paramBank = 0
            self?.syncBrowseToSelection()
            // ContentView observes AppModel, not the individual Track, so the
            // async load completing on a Track doesn't refresh it. Nudge AppModel
            // to re-render now that the AU exists (otherwise the plugin controls
            // only appear after switching tracks away and back).
            self?.objectWillChange.send()
        }
    }

    func setVolume(_ value: Float, for track: Track) {
        track.volume = value
        audio.setVolume(track.muted ? 0 : value, for: track.id)
    }

    func toggleMute(_ track: Track) {
        track.muted.toggle()
        audio.setVolume(track.muted ? 0 : track.volume, for: track.id)
    }

    /// Record-arm a track (single-arm: arming one disarms the rest, and selects
    /// it so the keyboard plays the track you're recording onto).
    func toggleArm(_ track: Track) {
        let newState = !track.armed
        for t in tracks { t.armed = false }
        track.armed = newState
        if newState { select(track) }
        objectWillChange.send()
        diag("app", "arm \(track.name) = \(newState)")
    }

    // MARK: - Song persistence (v2.1)

    private var songURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("auseq-song.json")
    }

    var hasSavedSong: Bool { FileManager.default.fileExists(atPath: songURL.path) }

    /// Build a serializable snapshot of the current session.
    func makeDocument() -> SongDocument {
        var trackDatas: [SongDocument.TrackData] = []
        for t in tracks {
            let (r, g, b, _) = Self.rgba(of: t.color)
            var td = SongDocument.TrackData(
                name: t.name, red: r, green: g, blue: b,
                volume: t.volume, pan: t.pan, muted: t.muted, midiChannel: t.midiChannel,
                instrumentName: t.instrumentName, hasInstrument: t.hasInstrument,
                componentType: nil, componentSubType: nil, componentManufacturer: nil,
                fullState: nil,
                notes: sequencer.clipNotes(for: t.id).map {
                    SongDocument.NoteData(time: $0.time, note: $0.note, velocity: $0.velocity, isOn: $0.isOn)
                })
            if let desc = audio.componentDescription(for: t.id) {
                td.componentType = desc.componentType
                td.componentSubType = desc.componentSubType
                td.componentManufacturer = desc.componentManufacturer
                if let state = audio.fullState(for: t.id) {
                    td.fullState = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
                }
            }
            trackDatas.append(td)
        }
        return SongDocument(
            bpm: sequencer.bpm, loopBars: sequencer.loopBars,
            quantizeOn: sequencer.quantizeOn, quantizeGrid: sequencer.quantizeGrid.rawValue,
            loopEnabled: sequencer.loopEnabled, countInEnabled: sequencer.countInEnabled,
            loopStartBeat: sequencer.loopStartBeat, loopEndBeat: sequencer.loopEndBeat,
            selectedTrackIndex: tracks.firstIndex { $0.id == selectedTrackID },
            tracks: trackDatas)
    }

    /// Snapshot the whole session to disk: settings, tracks (instrument identity +
    /// patch + mixer), and recorded notes.
    func saveSong() {
        let doc = makeDocument()
        do {
            let data = try JSONEncoder().encode(doc)
            try data.write(to: songURL, options: .atomic)
            diag("song", "saved \(doc.tracks.count) tracks")
        } catch {
            diag("song", "save FAILED: \(error.localizedDescription)")
        }
        objectWillChange.send()
    }

    /// Self-test (no plugin/ears needed): encode the live session to JSON, decode
    /// it back, and confirm the structural data survives the round-trip. Verifies
    /// the serialization layer (notes, settings, mixer, colors) on-device.
    func roundTripReport() -> String {
        let doc = makeDocument()
        let totalNotes = doc.tracks.reduce(0) { $0 + $1.notes.count }
        do {
            let data = try JSONEncoder().encode(doc)
            let back = try JSONDecoder().decode(SongDocument.self, from: data)
            let backNotes = back.tracks.reduce(0) { $0 + $1.notes.count }
            var checks: [(String, Bool)] = [
                ("tracks \(doc.tracks.count) → \(back.tracks.count)", doc.tracks.count == back.tracks.count),
                ("notes \(totalNotes) → \(backNotes)", totalNotes == backNotes),
                ("bpm \(Int(doc.bpm))", doc.bpm == back.bpm),
                ("bars \(doc.loopBars)", doc.loopBars == back.loopBars),
                ("grid \(doc.quantizeGrid)", doc.quantizeGrid == back.quantizeGrid),
                ("loop region", doc.loopStartBeat == back.loopStartBeat && doc.loopEndBeat == back.loopEndBeat),
            ]
            if let f = doc.tracks.first, let bf = back.tracks.first {
                checks.append(("track-1 color", f.red == bf.red && f.green == bf.green && f.blue == bf.blue))
                checks.append(("track-1 instrument id", f.componentSubType == bf.componentSubType))
            }
            let pass = checks.allSatisfy { $0.1 }
            let body = checks.map { "  \($0.1 ? "✓" : "✗") \($0.0)" }.joined(separator: "\n")
            return "\(pass ? "PASS" : "FAIL") — save/load round-trip (\(data.count) bytes)\n\(body)"
        } catch {
            return "FAIL — \(error.localizedDescription)"
        }
    }

    /// Rebuild the session from disk. Tracks get fresh IDs; clips are restored
    /// immediately, instruments re-instantiate (and reapply their patch) async.
    func loadSong() {
        // Run off the Menu button's SwiftUI transaction. Mutating tons of
        // @Published state (and tearing down the audio engine) synchronously
        // inside the tap action can force a re-render mid-mutation and crash;
        // deferring lets the menu dismiss and the view tree settle first.
        DiagLog.shared.beginBreadcrumbs("loadSong")
        crumb("scheduled (deferred off menu action)")
        DispatchQueue.main.async { [weak self] in self?.performLoadSong() }
    }

    private func performLoadSong() {
        crumb("read file")
        guard let data = try? Data(contentsOf: songURL),
              let doc = try? JSONDecoder().decode(SongDocument.self, from: data) else {
            diag("song", "load: no saved song"); crumb("ABORT: decode failed/no file"); return
        }
        crumb("decoded \(doc.tracks.count) tracks")
        sequencer.stop()
        crumb("removeAllTracks")
        audio.removeAllTracks()
        sequencer.clear()
        tracks.removeAll()
        crumb("set bpm \(doc.bpm)")
        sequencer.bpm = doc.bpm.isFinite ? doc.bpm : 120
        crumb("bpm ok")
        crumb("set loopBars \(doc.loopBars)")
        sequencer.loopBars = max(1, doc.loopBars)          // 0/neg would crash ForEach(0..<loopBars)
        crumb("set quantize")
        sequencer.quantizeOn = doc.quantizeOn
        sequencer.quantizeGrid = QuantizeGrid(rawValue: doc.quantizeGrid) ?? .d16
        crumb("set loop flags")
        sequencer.loopEnabled = doc.loopEnabled
        sequencer.countInEnabled = doc.countInEnabled
        crumb("set loop region \(doc.loopStartBeat)–\(doc.loopEndBeat)")
        sequencer.loopStartBeat = doc.loopStartBeat.isFinite ? max(0, doc.loopStartBeat) : 0
        sequencer.loopEndBeat = doc.loopEndBeat.isFinite ? max(0, doc.loopEndBeat) : 0
        crumb("settings done")

        for (i, td) in doc.tracks.enumerated() {
            crumb("track \(i): build '\(td.name)'")
            let color = Color(.sRGB, red: Double(td.red), green: Double(td.green), blue: Double(td.blue))
            let track = Track(name: td.name, color: color)
            track.volume = td.volume
            track.pan = td.pan
            track.muted = td.muted
            track.midiChannel = td.midiChannel
            track.instrumentName = td.instrumentName
            track.armed = false
            tracks.append(track)

            crumb("track \(i): load \(td.notes.count) notes")
            sequencer.loadClip(td.notes.map {
                Sequencer.NoteEvent(time: $0.time, note: $0.note, velocity: $0.velocity, isOn: $0.isOn)
            }, for: track.id)

            if td.hasInstrument,
               let type = td.componentType, let sub = td.componentSubType, let mfr = td.componentManufacturer {
                var desc = AudioComponentDescription()
                desc.componentType = type
                desc.componentSubType = sub
                desc.componentManufacturer = mfr
                let state = td.fullState.flatMap {
                    (try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil)) as? [String: Any]
                }
                crumb("track \(i): instantiate '\(td.instrumentName)' (state=\(state == nil ? "no" : "yes"))")
                audio.loadInstrument(description: desc, name: td.instrumentName, fullState: state, for: track.id) { [weak self] _ in
                    crumb("track instrument attached: \(td.instrumentName)")
                    track.hasInstrument = true
                    self?.audio.setVolume(track.muted ? 0 : track.volume, for: track.id)
                    self?.audio.setPan(track.pan, for: track.id)
                    self?.objectWillChange.send()
                }
            }
        }

        crumb("select track")
        if tracks.isEmpty {
            addTrack()
        } else {
            let idx = min(max(0, doc.selectedTrackIndex ?? 0), tracks.count - 1)
            selectedTrackID = tracks[idx].id
            setArmed(tracks[idx])
        }
        objectWillChange.send()
        crumb("loadSong returned OK (instruments may still be attaching)")
        diag("song", "loaded \(doc.tracks.count) tracks")
    }

    /// Resolve a SwiftUI Color to sRGB components for round-tripping to disk.
    static func rgba(of color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    // MARK: - Live input routing (keyboard + MIDI in)

    /// Which track each currently-held note was started on, so the note-off goes
    /// to the same track even if you switch tracks while holding a key.
    private var liveNoteTrack: [UInt8: UUID] = [:]

    func playNoteOn(_ note: UInt8, velocity: UInt8) {
        guard let track = selectedTrack else { return }
        liveNoteTrack[note] = track.id
        audio.noteOn(note, velocity: velocity, channel: track.midiChannel, to: track.id)
        sequencer.recordNoteOn(note, velocity: velocity)
    }

    func playNoteOff(_ note: UInt8) {
        let trackID = liveNoteTrack[note] ?? selectedTrackID
        liveNoteTrack[note] = nil
        if let trackID {
            let channel = tracks.first { $0.id == trackID }?.midiChannel ?? 0
            audio.noteOff(note, channel: channel, to: trackID)
        }
        sequencer.recordNoteOff(note)
    }

    private func handleIncoming(_ message: MIDIMessage, from source: String) {
        // The KeyLab's dedicated DAW/MCU port drives controls, not notes — route
        // it away from the instrument so transport buttons don't play stray notes.
        if isControlPort(source) {
            handleController(message)
            return
        }
        guard let track = selectedTrack else { return }
        switch message {
        case let .noteOn(note, velocity, _):
            playNoteOn(note, velocity: velocity)       // shared path: routing, hung-note tracking, recording
        case let .noteOff(note, _):
            playNoteOff(note)
        case let .controlChange(controller, value, _):
            audio.controlChange(controller, value: value, channel: track.midiChannel, to: track.id)
        case let .polyAftertouch(note, pressure, _):
            audio.sendMIDI([0xA0 | track.midiChannel, note, pressure], to: track.id)
        case let .channelAftertouch(pressure, _):
            audio.sendMIDI([0xD0 | track.midiChannel, pressure], to: track.id)
        case let .programChange(program, _):
            audio.sendMIDI([0xC0 | track.midiChannel, program], to: track.id)
        case let .transport(t):
            switch t {
            case .start, .continue: sequencer.play()    // external MIDI clock transport
            case .stop: sequencer.stop()
            }
        case .pitchBend, .other:
            break
        }
    }

    private func isControlPort(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains("daw")
    }

    // MARK: - KeyLab DAW-port controller (MCU)

    /// Encoders 1–9 = CC 16…24 ch1, relative. Maps encoder N to the selected
    /// track's parameter N (the same order shown in the parameter list).
    private func handleController(_ message: MIDIMessage) {
        switch message {
        case let .controlChange(cc, value, _) where (16...24).contains(cc):
            let index = Int(cc) - 16
            let delta = value < 0x40 ? Int(value) : -(Int(value) - 0x40)   // MCU relative
            nudgeParameter(index, by: delta)
        case let .controlChange(cc, value, _) where cc == 60:
            // KeyLab big knob (MCU jog wheel, CC 60, relative) → browse sounds on the wheel.
            let delta = value < 0x40 ? Int(value) : -(Int(value) - 0x40)
            browseStep(delta > 0 ? 1 : (delta < 0 ? -1 : 0))
        case let .controlChange(cc, value, _):
            diag("ctrl", "CC \(cc)=\(value)")   // log unmapped CCs (helps ID the big knob)
        case let .pitchBend(value, channel):
            // MCU faders = pitch bend per channel → that track's volume.
            setFaderVolume(channel: Int(channel), value: Float(value) / 16383.0)
        case let .noteOn(note, velocity, _) where velocity > 0:
            switch note {
            case 49: pageBank(1)    // KeyLab "Next" → next page of params
            case 48: pageBank(-1)   // KeyLab "Previous" → previous page
            case 94: sequencer.play()          // MCU Play
            case 93: sequencer.stop()          // MCU Stop
            case 95: sequencer.toggleRecord()  // MCU Record
            case 91: stepPreset(-1)            // MCU Rewind ◀◀ → previous preset
            case 92: stepPreset(1)             // MCU Forward ▶▶ → next preset
            case 24...31: selectTrackByIndex(Int(note) - 24)  // MCU Select buttons under faders
            case 0x65, 0x54: browseCommit()  // big-knob press (best guess: MCU scrub/zoom) → load browsed sound
            default: diag("ctrl", "note \(note) v\(velocity)")  // log unmapped notes (helps ID the big-knob press)
            }
        default:
            break
        }
    }

    /// Fader (channel 0…8) → the matching track's volume.
    private func setFaderVolume(channel: Int, value: Float) {
        guard channel >= 0, channel < tracks.count else { return }
        setVolume(value, for: tracks[channel])
    }

    /// Select button under fader N → make track N the selected track.
    private func selectTrackByIndex(_ index: Int) {
        guard index >= 0, index < tracks.count else { return }
        select(tracks[index])
        diag("ctrl", "KeyLab select → \(tracks[index].name)")
    }

    /// Step the selected plugin's factory preset (wraps around). Driven by the
    /// KeyLab's ◀◀ / ▶▶ buttons; the on-screen preset menu reflects the change.
    private func stepPreset(_ delta: Int) {
        guard let au = selectedAU, let presets = au.factoryPresets, !presets.isEmpty else { return }
        let curIdx = presets.firstIndex { $0.number == au.currentPreset?.number } ?? 0
        let idx = ((curIdx + delta) % presets.count + presets.count) % presets.count
        au.currentPreset = presets[idx]
        paramBank = 0
        objectWillChange.send()
        diag("ctrl", "preset → \(presets[idx].name)")
    }

    /// Light the KeyLab's Select-button LED for the selected track (MCU feedback:
    /// NoteOn the button's note, velocity 127 = on, 0 = off).
    func updateSelectLEDs() {
        let selected = tracks.firstIndex { $0.id == selectedTrackID }
        for i in 0..<8 {
            let on: UInt8 = (i == selected) ? 127 : 0
            midi.send([0x90, UInt8(24 + i), on], toPortNamed: "DAW")
        }
    }

    private func nudgeParameter(_ encoderIndex: Int, by delta: Int) {
        guard delta != 0,
              let au = selectedAU,
              let params = au.parameterTree?.allParameters else { return }
        let paramIndex = paramBank * Self.encoderCount + encoderIndex
        guard paramIndex < params.count else { return }
        let p = params[paramIndex]
        let span = p.maxValue - p.minValue
        guard span > 0 else { return }
        let step = span / 64                          // ~64 ticks across the full range
        let nv = min(p.maxValue, max(p.minValue, p.value + Float(delta) * step))
        p.setValue(nv, originator: nil)               // nil → the param-list observer updates the UI
    }
}
