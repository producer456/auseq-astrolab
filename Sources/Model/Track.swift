import Foundation
import SwiftUI

@MainActor
final class Track: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var instrumentName: String = "No instrument"
    @Published var hasInstrument = false
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
