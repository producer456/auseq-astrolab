import SwiftUI
import AVFoundation

/// Interactive AstroLab nav wheel: drag to scroll the instrument list (shown on
/// the wheel screen), tap to load the highlighted sound onto the selected track.
private struct SoundBrowserWheel: View {
    @ObservedObject var model: AppModel
    @State private var browseIndex = 0
    @State private var dragStartIndex: Int?

    private var instruments: [AVAudioUnitComponent] { model.browser.instruments }

    var body: some View {
        let count = instruments.count
        let idx = count > 0 ? min(max(0, browseIndex), count - 1) : 0
        let title = count > 0 ? instruments[idx].name : (model.selectedTrack?.instrumentName ?? "—")
        let sub = count > 0 ? "\(idx + 1)/\(count) · tap to load" : "no sounds"

        NavWheel(title: title, subtitle: sub, glyph: "waveform",
                 lit: model.selectedTrack?.hasInstrument ?? false, size: 88)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        guard count > 0 else { return }
                        if dragStartIndex == nil { dragStartIndex = idx }
                        let steps = Int(-v.translation.height / 22)
                        browseIndex = ((dragStartIndex! + steps) % count + count) % count
                    }
                    .onEnded { _ in dragStartIndex = nil }
            )
            .onTapGesture {
                guard count > 0, let track = model.selectedTrack else { return }
                model.assignInstrument(instruments[idx], to: track)
            }
            .onAppear {
                if let name = model.selectedTrack?.instrumentName,
                   let i = instruments.firstIndex(where: { $0.name == name }) {
                    browseIndex = i
                }
            }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showingConfig = false
    @State private var mainMode: MainMode = .params

    enum MainMode: String, CaseIterable { case params = "PARAMS", arrange = "ARRANGE" }

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
        .sheet(isPresented: $showingConfig) {
            ConfigurationView(model: model)
        }
    }

    private var mainArea: some View {
        VStack(spacing: 0) {
            topBar
            GoldHairline()
            TransportBar(seq: model.sequencer,
                         onQuantizeSelected: { model.quantizeSelected() },
                         onQuantizeAll: { model.quantizeAll() })
            GoldHairline()
            modePicker
            if mainMode == .arrange {
                ArrangeView(model: model, seq: model.sequencer)
            } else {
                if let track = model.selectedTrack, track.hasInstrument, let au = model.selectedAU {
                    ParameterListView(au: au, model: model)
                        .id(track.id)   // rebuild when the selected track changes
                } else {
                    Spacer()
                    status
                    Spacer()
                }
                if model.selectedTrack != nil {
                    ClipView(seq: model.sequencer, trackID: model.selectedTrackID)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
            }
            PianoKeyboardView(model: model)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mainMode) {
            ForEach(MainMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ASTROLAB")
                    .font(Theme.mono(24, .heavy))
                    .tracking(3)
                    .foregroundStyle(Theme.etched)
                Text(midiSummary).etchedLabel(9, soft: true, weight: .medium)
            }
            Button { showingConfig = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3).foregroundStyle(Theme.orange)
            }
            Spacer()
            // Navigation wheel — scroll to browse sounds, tap to load
            SoundBrowserWheel(model: model)
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
