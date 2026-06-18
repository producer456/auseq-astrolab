import Foundation
import SwiftUI

@MainActor
final class Track: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var instrumentName: String = "No instrument"
    @Published var hasInstrument = false
    /// Bumped each time an instrument is (re)loaded — a stable key for rebuilding
    /// the param view (more reliable than the AU's heap address, which can be reused).
    @Published var instrumentGen = 0
    @Published var volume: Float = 0.8
    @Published var pan: Float = 0
    @Published var muted = false
    @Published var armed = false

    /// MIDI channel this track listens/records on (0-based). 0 = omni-ish for now.
    var midiChannel: UInt8 = 0
    var color: Color

    init(name: String, color: Color) {
        self.name = name
        self.color = color
    }
}
