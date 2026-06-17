import Foundation
import AVFoundation
import AudioToolbox

/// Multi-track AUv3 host. Each track owns an instrument node feeding a
/// per-track mixer (for volume/pan) into the main mixer.
@MainActor
final class AudioEngine: ObservableObject {

    let engine = AVAudioEngine()

    private struct TrackAudio {
        let unit: AVAudioUnit
        let mixer: AVAudioMixerNode
        let scheduleMIDI: AUScheduleMIDIEventBlock?
        let name: String
        let desc: AudioComponentDescription   // kept so a song can re-instantiate this plugin
    }

    private var hosts: [UUID: TrackAudio] = [:]
    @Published var lastError: String?
    @Published private(set) var loadingTrackIDs: Set<UUID> = []

    // Metronome click — a player node fed short enveloped sine bursts.
    private let clickPlayer = AVAudioPlayerNode()
    private let clickFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var clickHi: AVAudioPCMBuffer?
    private var clickLo: AVAudioPCMBuffer?
    private var clickReady = false
    private var clickNeedsRestart = false   // set when the engine stops; forces a clean player restart

    init() {
        configureSession()
    }

    // MARK: - Session / engine lifecycle

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
        }
    }

    func start() {
        guard !engine.isRunning else { return }
        // Realize the output node before starting. Accessing mainMixerNode
        // lazily creates the main mixer and connects it to the output node,
        // so the graph has valid I/O even when no instrument is attached yet
        // (otherwise AVAudioEngine asserts inputNode/outputNode != nullptr and
        // the app crashes on launch / after the last track is removed).
        _ = engine.mainMixerNode
        setupClickIfNeeded()
        engine.prepare()
        do {
            try engine.start()
            clickNeedsRestart = true     // force a clean click-player restart after any (re)start
            diag("audio", "engine started")
        } catch {
            lastError = "Engine start: \(error.localizedDescription)"
            diag("audio", "engine start FAILED: \(error.localizedDescription)")
        }
    }

    // MARK: - Metronome

    private func setupClickIfNeeded() {
        guard !clickReady else { return }
        engine.attach(clickPlayer)
        engine.connect(clickPlayer, to: engine.mainMixerNode, format: clickFormat)
        clickHi = makeClick(freq: 1600)
        clickLo = makeClick(freq: 1000)
        clickReady = true
    }

    private func makeClick(freq: Float) -> AVAudioPCMBuffer? {
        let sr = Float(clickFormat.sampleRate)
        let n = AVAudioFrameCount(0.035 * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: clickFormat, frameCapacity: n) else { return nil }
        buf.frameLength = n
        let p = buf.floatChannelData![0]
        for i in 0..<Int(n) {
            let t = Float(i) / sr
            let env = expf(-Float(i) / Float(n) * 6)        // fast decay → a tick
            p[i] = sinf(2 * .pi * freq * t) * env * 0.4
        }
        return buf
    }

    /// Play one metronome tick (high pitch on the downbeat).
    func click(downbeat: Bool) {
        guard clickReady, engine.isRunning, let buf = downbeat ? clickHi : clickLo else { return }
        // After an engine stop/start (e.g. loading a plugin), the player's state
        // is stale — stop & re-play it so scheduled buffers actually render.
        if clickNeedsRestart {
            clickPlayer.stop()
            clickPlayer.play()
            clickNeedsRestart = false
            diag("audio", "metronome player restarted")
        } else if !clickPlayer.isPlaying {
            clickPlayer.play()
        }
        clickPlayer.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Per-track instrument loading

    func loadInstrument(_ component: AVAudioUnitComponent,
                        for trackID: UUID,
                        completion: @escaping (String) -> Void) {
        loadingTrackIDs.insert(trackID)
        let desc = component.audioComponentDescription
        let name = component.name

        AVAudioUnit.instantiate(with: desc, options: [.loadOutOfProcess]) { [weak self] unit, error in
            Task { @MainActor in
                guard let self else { return }
                self.loadingTrackIDs.remove(trackID)
                if let error {
                    self.lastError = "Load \(name): \(error.localizedDescription)"
                    return
                }
                guard let unit else {
                    self.lastError = "Load \(name): no audio unit"
                    return
                }
                self.attach(unit, name: name, desc: desc, to: trackID)
                completion(name)
            }
        }
    }

    /// Re-instantiate an instrument from a saved AUv3 identity + restore its full
    /// state (the patch). Used when loading a song.
    func loadInstrument(description desc: AudioComponentDescription,
                        name: String,
                        fullState: [String: Any]?,
                        for trackID: UUID,
                        completion: @escaping (String) -> Void) {
        loadingTrackIDs.insert(trackID)
        AVAudioUnit.instantiate(with: desc, options: [.loadOutOfProcess]) { [weak self] unit, error in
            Task { @MainActor in
                guard let self else { return }
                self.loadingTrackIDs.remove(trackID)
                if let error {
                    self.lastError = "Load \(name): \(error.localizedDescription)"
                    return
                }
                guard let unit else {
                    self.lastError = "Load \(name): no audio unit"
                    return
                }
                crumb("AE: instantiated \(name), attaching")
                self.attach(unit, name: name, desc: desc, to: trackID)
                completion(name)
                // Restore the saved patch only AFTER the unit is attached and the
                // engine is running, on a later runloop turn. Setting fullState on
                // a just-instantiated unit can put it in a state that aborts when
                // the engine allocates render resources — deferring is safer. Wrap
                // in @try/@catch for any ObjC throw (the C++ abort case is logged
                // via the breadcrumb written just before).
                if let fullState {
                    DispatchQueue.main.async {
                        crumb("AE: applying fullState to \(name)")
                        if let err = AUSeqTryCatch({ unit.auAudioUnit.fullState = fullState }) {
                            self.lastError = "Restore patch \(name): \(err.localizedDescription)"
                            diag("audio", "fullState restore threw: \(err.localizedDescription)")
                        }
                        crumb("AE: fullState applied to \(name)")
                    }
                }
            }
        }
    }

    private func attach(_ unit: AVAudioUnit, name: String, desc: AudioComponentDescription, to trackID: UUID) {
        diag("audio", "attach instrument '\(name)' (engine was \(engine.isRunning ? "running" : "stopped"))")
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop(); clickNeedsRestart = true }

        removeHostNodes(trackID)

        let mixer = AVAudioMixerNode()
        engine.attach(unit)
        engine.attach(mixer)
        crumb("AE: connect \(name)")
        // nil format → the engine infers from the node, which is safer than
        // reading outputFormat while the engine is stopped (some AUv3s report a
        // stale/invalid format then, throwing on start and silencing the track).
        // Wrap the connects: a misbehaving plugin can throw an ObjC exception
        // here, which would otherwise crash the app on load.
        if let err = AUSeqTryCatch({
            self.engine.connect(unit, to: mixer, format: nil)
            self.engine.connect(mixer, to: self.engine.mainMixerNode, format: nil)
        }) {
            lastError = "Connect \(name): \(err.localizedDescription)"
            diag("audio", "connect threw: \(err.localizedDescription)")
            engine.detach(unit); engine.detach(mixer)
            start()
            return
        }
        crumb("AE: connected \(name), starting engine")

        hosts[trackID] = TrackAudio(
            unit: unit,
            mixer: mixer,
            scheduleMIDI: unit.auAudioUnit.scheduleMIDIEventBlock,
            name: name,
            desc: desc
        )
        start()
    }

    private func removeHostNodes(_ trackID: UUID) {
        guard let host = hosts[trackID] else { return }
        engine.disconnectNodeOutput(host.unit)
        engine.disconnectNodeOutput(host.mixer)
        engine.detach(host.unit)
        engine.detach(host.mixer)
        hosts[trackID] = nil
    }

    func removeTrack(_ trackID: UUID) {
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop(); clickNeedsRestart = true }
        removeHostNodes(trackID)
        start()
    }

    /// Tear down every track's nodes with a single engine stop/start — used when
    /// loading a song, to avoid churning the engine once per track (which can
    /// trip AVAudioEngine assertions).
    func removeAllTracks() {
        if engine.isRunning { engine.stop(); clickNeedsRestart = true }
        for id in Array(hosts.keys) { removeHostNodes(id) }
        start()
    }

    func hasInstrument(_ trackID: UUID) -> Bool { hosts[trackID] != nil }

    /// The hosted AUAudioUnit for a track (used by the parameter/preset UI later).
    func auAudioUnit(for trackID: UUID) -> AUAudioUnit? {
        hosts[trackID]?.unit.auAudioUnit
    }

    /// AUv3 identity of a track's loaded instrument (for saving a song).
    func componentDescription(for trackID: UUID) -> AudioComponentDescription? {
        hosts[trackID]?.desc
    }

    /// The loaded instrument's full state / patch (for saving a song).
    func fullState(for trackID: UUID) -> [String: Any]? {
        hosts[trackID]?.unit.auAudioUnit.fullState
    }

    // MARK: - Mixer control

    func setVolume(_ value: Float, for trackID: UUID) {
        hosts[trackID]?.mixer.outputVolume = max(0, min(1, value))
    }

    func setPan(_ value: Float, for trackID: UUID) {
        hosts[trackID]?.mixer.pan = max(-1, min(1, value))
    }

    // MARK: - MIDI out to a track's instrument

    func sendMIDI(_ bytes: [UInt8], to trackID: UUID) {
        guard let block = hosts[trackID]?.scheduleMIDI else { return }
        bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            block(AUEventSampleTimeImmediate, 0, buf.count, base)
        }
    }

    func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8 = 0, to trackID: UUID) {
        sendMIDI([0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F], to: trackID)
    }

    func noteOff(_ note: UInt8, channel: UInt8 = 0, to trackID: UUID) {
        sendMIDI([0x80 | (channel & 0x0F), note & 0x7F, 0], to: trackID)
    }

    func controlChange(_ controller: UInt8, value: UInt8, channel: UInt8 = 0, to trackID: UUID) {
        sendMIDI([0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F], to: trackID)
    }

    func allNotesOff(to trackID: UUID, channel: UInt8 = 0) {
        sendMIDI([0xB0 | (channel & 0x0F), 123, 0], to: trackID)
    }
}
