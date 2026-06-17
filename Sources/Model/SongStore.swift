import Foundation
import CoreGraphics

/// On-disk song format (v2.1). Plain Codable → JSON in the app's Documents dir.
/// Captures everything needed to rebuild a session: transport/grid settings, the
/// tracks (instrument identity + full plugin state + mixer), and the recorded
/// notes per track. `NoteEvent` times are in beats, so a song is tempo-portable.
struct SongDocument: Codable {
    var version = 1
    var bpm: Double
    var loopBars: Int
    var quantizeOn: Bool
    var quantizeGrid: String          // QuantizeGrid.rawValue
    var loopEnabled: Bool
    var countInEnabled: Bool
    var loopStartBeat: Double
    var loopEndBeat: Double
    var selectedTrackIndex: Int?
    var tracks: [TrackData]

    struct TrackData: Codable {
        var name: String
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var volume: Float
        var pan: Float
        var muted: Bool
        var midiChannel: UInt8
        var instrumentName: String
        var hasInstrument: Bool
        // AUv3 identity, so the same plugin can be re-instantiated on load.
        var componentType: UInt32?
        var componentSubType: UInt32?
        var componentManufacturer: UInt32?
        var fullState: Data?          // plist-serialized AUAudioUnit.fullState (the patch)
        var notes: [NoteData]
    }

    struct NoteData: Codable {
        var time: Double              // beats
        var note: UInt8
        var velocity: UInt8
        var isOn: Bool
    }
}
