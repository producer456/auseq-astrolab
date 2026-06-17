import Foundation
import CoreMIDI

enum MIDIMessage {
    case noteOn(note: UInt8, velocity: UInt8, channel: UInt8)
    case noteOff(note: UInt8, channel: UInt8)
    case controlChange(controller: UInt8, value: UInt8, channel: UInt8)
    case pitchBend(value: UInt16, channel: UInt8)
    case polyAftertouch(note: UInt8, pressure: UInt8, channel: UInt8)
    case channelAftertouch(pressure: UInt8, channel: UInt8)
    case programChange(program: UInt8, channel: UInt8)
    case transport(Transport)            // incoming MIDI clock transport
    case other

    enum Transport { case start, `continue`, stop }
}

/// One captured raw MIDI message, tagged with its source port — for the M5
/// monitor used to decode the KeyLab DAW port.
struct MIDIMonitorEntry: Identifiable {
    let id = UUID()
    let source: String
    let status: UInt8
    let d1: UInt8
    let d2: UInt8

    var hex: String { String(format: "%02X %02X %02X", status, d1, d2) }

    var decoded: String {
        let ch = (status & 0x0F) + 1
        switch status & 0xF0 {
        case 0x90 where d2 > 0: return "NOTE ON   n=\(d1) v=\(d2) ch\(ch)"
        case 0x90, 0x80:        return "NOTE OFF  n=\(d1) ch\(ch)"
        case 0xB0:
            if (0x10...0x17).contains(d1) {  // MCU relative encoder
                let dir = d2 < 0x40 ? "CW +\(d2)" : "CCW -\(d2 - 0x40)"
                return "ENC \(d1 - 0x10)  \(dir) (CC\(d1) ch\(ch))"
            }
            return "CC        ctrl=\(d1) val=\(d2) ch\(ch)"
        case 0xE0: return "PITCHBEND \(UInt16(d1) | (UInt16(d2) << 7)) ch\(ch)"
        default:   return "status \(String(format: "%02X", status))"
        }
    }
}

/// CoreMIDI input. Connects to every available source (the KeyLab's ports show
/// up here over USB) and forwards parsed MIDI 1.0 messages on the main queue.
/// The dedicated DAW-port / MCU handling for the KeyLab arrives in M5; this is
/// the plain note/CC path used for live play and recording.
final class MIDIManager: ObservableObject {

    @Published private(set) var sourceNames: [String] = []
    /// Parsed message + the source port name (so the app can route the KeyLab's
    /// DAW/MCU port to controller handling instead of the note path).
    var onMessage: ((MIDIMessage, String) -> Void)?

    /// Raw-MIDI monitor (M5). When `isMonitoring` is on, every parsed message is
    /// captured (tagged with its source port) into `monitorEntries`, newest last.
    @Published var isMonitoring = false
    @Published private(set) var monitorEntries: [MIDIMonitorEntry] = []
    private let monitorCap = 400
    /// Live per-message hook (main queue) used by the guided Controller Learn flow.
    var onMonitor: ((MIDIMonitorEntry) -> Void)?

    func clearMonitor() { monitorEntries.removeAll() }

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    /// refCon token (source index + 1) → display name, so the read block can tag
    /// each message with the port it came from.
    private var nameByToken: [Int: String] = [:]

    func start() {
        if client == 0 {
            MIDIClientCreateWithBlock("AUSeq" as CFString, &client) { [weak self] _ in
                DispatchQueue.main.async { self?.connectAllSources() }
            }
        }
        if inputPort == 0 {
            MIDIInputPortCreateWithProtocol(client, "AUSeq In" as CFString, ._1_0, &inputPort) { [weak self] listPtr, srcConnRefCon in
                // CoreMIDI thread: copy the raw words, then do ALL parsing and
                // shared-state access (nameByToken, monitor, callbacks) on main.
                let token = srcConnRefCon.map { Int(bitPattern: $0) } ?? 0
                let words = MIDIManager.extractWords(listPtr)
                DispatchQueue.main.async { self?.process(words: words, token: token) }
            }
        }
        if outputPort == 0 {
            MIDIOutputPortCreate(client, "AUSeq Out" as CFString, &outputPort)
        }
        connectAllSources()
    }

    /// Names of available MIDI destinations (for picking the KeyLab DAW port).
    var destinationNames: [String] {
        (0..<MIDIGetNumberOfDestinations()).map { displayName(of: MIDIGetDestination($0)) }
    }

    private func destination(matching needle: String) -> MIDIEndpointRef? {
        for i in 0..<MIDIGetNumberOfDestinations() {
            let dst = MIDIGetDestination(i)
            if displayName(of: dst).localizedCaseInsensitiveContains(needle) { return dst }
        }
        return nil
    }

    /// Send raw bytes (incl. SysEx) to the first destination whose name contains
    /// `needle` (default the KeyLab DAW port). Uses the legacy MIDIPacketList,
    /// which is the simplest reliable path for SysEx.
    @discardableResult
    func send(_ bytes: [UInt8], toPortNamed needle: String = "DAW") -> Bool {
        guard outputPort != 0, !bytes.isEmpty, let dst = destination(matching: needle) else { return false }
        var storage = [UInt8](repeating: 0, count: 256 + bytes.count)
        return storage.withUnsafeMutableBytes { raw -> Bool in
            let listPtr = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            var pkt = MIDIPacketListInit(listPtr)
            pkt = MIDIPacketListAdd(listPtr, raw.count, pkt, 0, bytes.count, bytes)
            return MIDISend(outputPort, dst, listPtr) == noErr
        }
    }

    private func connectAllSources() {
        let count = MIDIGetNumberOfSources()
        var names: [String] = []
        nameByToken.removeAll()
        for i in 0..<count {
            let src = MIDIGetSource(i)
            guard src != 0 else { continue }
            let token = i + 1
            MIDIPortConnectSource(inputPort, src, UnsafeMutableRawPointer(bitPattern: token))
            let nm = displayName(of: src)
            nameByToken[token] = nm
            names.append(nm)
        }
        sourceNames = names
    }

    /// CoreMIDI-thread helper: copy all UMP words out of the event list (touches
    /// no shared mutable state).
    private static func extractWords(_ listPtr: UnsafePointer<MIDIEventList>) -> [UInt32] {
        var out: [UInt32] = []
        let numPackets = Int(listPtr.pointee.numPackets)
        guard numPackets > 0, let offset = MemoryLayout<MIDIEventList>.offset(of: \.packet) else { return out }
        var p = UnsafeRawPointer(listPtr).advanced(by: offset).assumingMemoryBound(to: MIDIEventPacket.self)
        for _ in 0..<numPackets {
            let wordCount = Int(p.pointee.wordCount)
            withUnsafeBytes(of: p.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                for i in 0..<min(wordCount, words.count) { out.append(words[i]) }
            }
            p = UnsafePointer(MIDIEventPacketNext(p))
        }
        return out
    }

    /// Main thread: resolve the source name and parse each word.
    private func process(words: [UInt32], token: Int) {
        let source = nameByToken[token] ?? "?"
        for w in words { parse(w, source: source) }
    }

    private func parse(_ word: UInt32, source: String) {
        // MIDI 1.0 UMP: channel-voice (message type 0x2) or system (type 0x1). On main.
        let mt = (word >> 28) & 0xF
        guard mt == 0x2 || mt == 0x1 else { return }
        let status = UInt8((word >> 16) & 0xFF)
        let d1 = UInt8((word >> 8) & 0x7F)
        let d2 = UInt8(word & 0x7F)
        let channel = status & 0x0F

        if isMonitoring {
            let entry = MIDIMonitorEntry(source: source, status: status, d1: d1, d2: d2)
            monitorEntries.append(entry)
            if monitorEntries.count > monitorCap {
                monitorEntries.removeFirst(monitorEntries.count - monitorCap)
            }
            onMonitor?(entry)
        }

        let message: MIDIMessage
        if mt == 0x1 {                                  // system real-time transport
            switch status {
            case 0xFA: message = .transport(.start)
            case 0xFB: message = .transport(.continue)
            case 0xFC: message = .transport(.stop)
            default:   message = .other
            }
        } else {
            switch status & 0xF0 {
            case 0x90: message = d2 == 0 ? .noteOff(note: d1, channel: channel)
                                         : .noteOn(note: d1, velocity: d2, channel: channel)
            case 0x80: message = .noteOff(note: d1, channel: channel)
            case 0xA0: message = .polyAftertouch(note: d1, pressure: d2, channel: channel)
            case 0xB0: message = .controlChange(controller: d1, value: d2, channel: channel)
            case 0xC0: message = .programChange(program: d1, channel: channel)
            case 0xD0: message = .channelAftertouch(pressure: d1, channel: channel)
            case 0xE0: message = .pitchBend(value: UInt16(d1) | (UInt16(d2) << 7), channel: channel)
            default:   message = .other
            }
        }
        onMessage?(message, source)
    }

    private func displayName(of obj: MIDIObjectRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &name) == noErr,
           let cf = name?.takeRetainedValue() {
            return cf as String
        }
        return "MIDI Source"
    }
}
