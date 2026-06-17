import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        ZStack {
            BrushedAluminum()
            HStack(spacing: 0) {
                WoodPanel().frame(width: 16).ignoresSafeArea()
                TrackListView(model: model)
                    .frame(width: 340)
                    .background(Theme.rail)
                Rectangle().fill(Theme.gold.opacity(0.5)).frame(width: 1)
                mainArea
                WoodPanel().frame(width: 16).ignoresSafeArea()
            }
        }
        .tint(Theme.orange)
        .preferredColorScheme(.light)
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            topBar
            GoldHairline()
            if let track = model.selectedTrack, track.hasInstrument, let au = model.selectedAU {
                ParameterListView(au: au)
                    .id(track.id)   // rebuild when the selected track changes
            } else {
                Spacer()
                status
                Spacer()
            }
            PianoKeyboardView(model: model)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("AUSEQ")
                    .font(Theme.mono(26, .heavy))
                    .tracking(2)
                    .foregroundStyle(Theme.etched)
                Text(midiSummary).etchedLabel(9, soft: true, weight: .medium)
            }
            Spacer()
            if let track = model.selectedTrack {
                HStack(spacing: 8) {
                    AmberLED(on: track.hasInstrument)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(track.name).font(.headline).foregroundStyle(track.color)
                        Text(track.instrumentName).etchedLabel(9, soft: true, weight: .medium).lineLimit(1)
                    }
                }
            }
        }
        .padding()
    }

    private var midiSummary: String {
        let n = model.midi.sourceNames.count
        if n == 0 { return "No MIDI inputs — connect the KeyLab" }
        return "MIDI in: " + model.midi.sourceNames.joined(separator: ", ")
    }

    @ViewBuilder
    private var status: some View {
        if let err = model.audio.lastError {
            Text(err).font(.footnote).foregroundStyle(.red)
                .multilineTextAlignment(.center).padding()
        } else if let track = model.selectedTrack, !track.hasInstrument {
            VStack(spacing: 18) {
                PerforatedGrille()
                    .frame(width: 160, height: 90)
                    .mask(RoundedRectangle(cornerRadius: 8))
                Text("Tap the keyboard icon on \(track.name) to load an AUv3 instrument, then play the keys or the KeyLab.")
                    .etchedLabel(11, soft: true, weight: .medium)
                    .tracking(0.5)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 40)
            }
        } else if let track = model.selectedTrack {
            Text("Playing \(track.instrumentName) on \(track.name)")
                .etchedLabel(12, weight: .semibold)
                .foregroundStyle(Theme.orange)
        }
    }
}

#Preview {
    ContentView()
}
