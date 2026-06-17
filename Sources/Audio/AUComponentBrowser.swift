import Foundation
import AVFoundation
import AudioToolbox
import Combine

/// Enumerates AUv3 components installed on the device, split by role.
@MainActor
final class AUComponentBrowser: ObservableObject {

    @Published private(set) var instruments: [AVAudioUnitComponent] = []
    @Published private(set) var effects: [AVAudioUnitComponent] = []

    func refresh() {
        instruments = components(ofType: kAudioUnitType_MusicDevice)
        // Effects can be either "aufx" or music effects "aumf".
        let fx = components(ofType: kAudioUnitType_Effect)
        let mfx = components(ofType: kAudioUnitType_MusicEffect)
        effects = (fx + mfx).sorted { $0.name < $1.name }
    }

    private func components(ofType type: OSType) -> [AVAudioUnitComponent] {
        var desc = AudioComponentDescription()
        desc.componentType = type
        desc.componentSubType = 0
        desc.componentManufacturer = 0
        desc.componentFlags = 0
        desc.componentFlagsMask = 0
        return AVAudioUnitComponentManager.shared()
            .components(matching: desc)
            .sorted { $0.name < $1.name }
    }
}

extension AVAudioUnitComponent {
    /// "Manufacturer — Name" for display.
    var displayName: String {
        manufacturerName.isEmpty ? name : "\(manufacturerName) — \(name)"
    }
}
