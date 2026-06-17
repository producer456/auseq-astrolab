import SwiftUI
import AVFoundation

/// Interactive AstroLab nav wheel: drag to scroll the instrument list (shown on
/// the wheel screen), tap to load the highlighted sound onto the selected track.
struct SoundBrowserWheel: View {
    @ObservedObject var model: AppModel
    var size: CGFloat = 88
    @State private var dragStart: Int?

    private var instruments: [AVAudioUnitComponent] { model.browser.instruments }

    var body: some View {
        let count = instruments.count
        let bidx = count > 0 ? min(max(0, model.browseIndex), count - 1) : 0
        let browsed = count > 0 ? instruments[bidx].name : nil
        let loaded = model.selectedTrack?.instrumentName
        let hasInst = model.selectedTrack?.hasInstrument ?? false
        // Browse + load happen ON the screen — no pop-out. Drag (or the KeyLab jog)
        // browses; tap (or jog press) loads the shown sound onto the selected track.
        let title = browsed ?? (hasInst ? (loaded ?? "—") : "LOAD")
        let pending = browsed != nil && (!hasInst || browsed != loaded)
        let sub = count == 0 ? "no sounds"
                             : (pending ? "tap / press to load" : "turn to browse")
        // LED ring = position in the sound list while browsing.
        let prog = count > 1 ? Double(bidx) / Double(count - 1) : (count == 1 ? 1 : 0)

        NavWheel(title: title, subtitle: sub, glyph: "waveform", lit: hasInst, size: size, progress: prog)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        guard count > 0 else { return }
                        if dragStart == nil { dragStart = model.browseIndex }
                        let steps = Int(-v.translation.height / 20)
                        model.browseIndex = (((dragStart ?? 0) + steps) % count + count) % count
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture { model.browseCommit() }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showingConfig = false
    @State private var showingTracks = false
    @State private var keyboardVisible = false   // fallback only — opened on demand when no controller
    @State private var showingPluginUI = false
    @AppStorage("woodTone") private var woodToneRaw = WoodTone.oak.rawValue
    @Environment(\.horizontalSizeClass) private var hSize

    private var isPhone: Bool { hSize == .compact }
    private var woodTone: WoodTone { WoodTone(rawValue: woodToneRaw) ?? .oak }

    var body: some View {
        Group {
            if isPhone { phoneBody } else { padBody }
        }
        .tint(Theme.orange)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showingConfig) {
            ConfigurationView(model: model)
        }
        .sheet(isPresented: $showingPluginUI) {
            if let au = model.selectedAU {
                NavigationStack {
                    AUPluginUIView(au: au)
                        .ignoresSafeArea()
                        .navigationTitle(model.selectedTrack?.instrumentName ?? "Plugin")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingPluginUI = false } } }
                }
                // Resizable by the user — drag between sizes.
                .presentationDetents([.height(360), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.resizes)
            }
        }
        .sheet(isPresented: $showingTracks) {
            NavigationStack {
                TrackListView(model: model)
                    .navigationTitle("Tracks")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingTracks = false } } }
            }
        }
    }

    /// iPad — edge-to-edge faceplate (fills to the iPad's bezel on all sides);
    /// wood-deck header runs to the top edge, the rail sits beside the content.
    private var padBody: some View {
        ZStack(alignment: .top) {
            faceplate.ignoresSafeArea()
            VStack(spacing: 0) {
                woodPanel
                panelGroove
                contentColumn
                    .recessedPanel(radius: 16)                               // display module sunk into the chassis
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, keyboardVisible ? 6 : 12)
                if keyboardVisible {
                    PianoKeyboardView(model: model, height: 190)
                        .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
    }

    /// Phone — edge-to-edge; tracks open in a drawer.
    private var phoneBody: some View {
        ZStack(alignment: .top) {
            faceplate.ignoresSafeArea()
            VStack(spacing: 0) {
                woodPanel
                panelGroove
                contentColumn
                    .recessedPanel(radius: 14)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, keyboardVisible ? 4 : 8)
                if keyboardVisible {
                    PianoKeyboardView(model: model, height: 140)
                        .padding(.horizontal, 8).padding(.bottom, 8)
                }
            }
        }
    }

    /// The content area below the wood control panel — the arranger fills it now
    /// that the parameters live as knobs in the wood.
    private var contentColumn: some View {
        ArrangeView(model: model, seq: model.sequencer, onEditTracks: { showingTracks = true })
    }

    /// Brushed-aluminium faceplate fill (no safe-area bleed — it's inset in the bezel).
    private var faceplate: some View {
        ZStack(alignment: .top) {
            Theme.surface
            RadialGradient(colors: [.clear, .black.opacity(0.05)], center: .center, startRadius: 240, endRadius: 820)
            LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
        }
    }

    /// Recessed edge: bright top lip → dark bottom, so the plate reads as set into the bezel.
    private func faceplateEdge(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.08), .black.opacity(0.40)],
                                         startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
    }

    /// PARAMS panel — the selected track's plugin parameters (or empty-state) plus
    /// its clip strip.
    private var paramsRegion: some View {
        VStack(spacing: 0) {
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
    }

    private var topBar: some View {
        let well: CGFloat = isPhone ? 32 : 36
        let icon: CGFloat = isPhone ? 13 : 15
        return VStack(spacing: isPhone ? 3 : 4) {
            // Slim control strip: branding + utilities, milled into the wood
            HStack(spacing: isPhone ? 8 : 12) {
                if isPhone {
                    Button { showingTracks = true } label: {
                        Image(systemName: "list.bullet").font(.system(size: icon, weight: .semibold))
                            .foregroundStyle(Theme.orange).woodInlay(size: well, tone: woodTone)
                    }
                }
                Text("KEYLAB")
                    .font(Theme.mono(isPhone ? 16 : 22, .heavy))
                    .tracking(isPhone ? 2 : 3.5)
                    .foregroundStyle(woodTone.ink)
                    .shadow(color: .black.opacity(0.45), radius: 0.5, y: 1)        // engraved (dark below)
                    .shadow(color: woodTone.light.opacity(0.5), radius: 0.5, y: -0.5) // top sheen
                // Relocated: preset readout + plugin's own UI (when an instrument is loaded)
                if model.selectedAU != nil {
                    Menu {
                        if model.presets.isEmpty {
                            Text("No factory presets")
                        } else {
                            ForEach(model.presets, id: \.number) { p in
                                Button { model.applyPreset(p) } label: {
                                    if p.number == model.selectedAU?.currentPreset?.number {
                                        Label(p.name, systemImage: "checkmark")
                                    } else { Text(p.name) }
                                }
                            }
                        }
                    } label: {
                        Text(model.currentPresetName)
                            .font(Theme.mono(11, .bold)).foregroundStyle(Theme.orange)
                            .lineLimit(1).frame(maxWidth: 120)
                            .metalInlayPill(tone: woodTone, hPad: 10, vPad: 8)
                    }
                    Button { showingPluginUI = true } label: {
                        InlaidMetalButton(system: "rectangle.inset.filled", lit: true, tint: Theme.orange, size: well, tone: woodTone)
                    }
                }
                Spacer()
                // Wood finish toggle — LED glows the tone you'll switch TO
                Button { woodToneRaw = woodTone.next.rawValue } label: {
                    InlaidMetalButton(system: "circle.fill", lit: true, tint: woodTone.next.light, size: well, tone: woodTone)
                }
                Menu {
                    Button { model.saveSong() } label: { Label("Save Song", systemImage: "square.and.arrow.down") }
                    Button { model.loadSong() } label: { Label("Open Last Song", systemImage: "tray.and.arrow.up") }
                        .disabled(!model.hasSavedSong)
                } label: {
                    InlaidMetalButton(system: "folder.fill", lit: true, tint: Theme.orange, size: well, tone: woodTone)
                }
                Button { showingConfig = true } label: {
                    InlaidMetalButton(system: "gearshape.fill", lit: true, tint: Theme.orange, size: well, tone: woodTone)
                }
                Button { keyboardVisible.toggle() } label: {
                    InlaidMetalButton(system: "pianokeys", lit: keyboardVisible, tint: Theme.orange, size: well, tone: woodTone)
                }
            }
            // The "screen" — big nav wheel; on iPad it's flanked by 8 inlaid param knobs.
            if isPhone {
                SoundBrowserWheel(model: model, size: 104).frame(height: 96)
            } else {
                WheelKnobDeck(model: model, tone: woodTone, wheelSize: 168, reservedHeight: 120)
            }
        }
        .padding(.horizontal, isPhone ? 12 : 16)
        .padding(.top, isPhone ? 5 : 7)
        .padding(.bottom, isPhone ? 3 : 5)
        .frame(maxWidth: .infinity)
    }

    /// The whole wooden control panel: branding + screen/knobs + transport, all
    /// on one continuous wood plane.
    private var woodPanel: some View {
        VStack(spacing: 0) {
            topBar
            TransportBar(seq: model.sequencer,
                         onQuantizeSelected: { model.quantizeSelected() },
                         onQuantizeAll: { model.quantizeAll() },
                         compact: isPhone, tone: woodTone)
        }
        // Wood fills behind the status bar up to the top edge; content stays below it.
        .background(WoodDeck(tone: woodTone).ignoresSafeArea(edges: .top))
    }

    /// Seam between the wood panel and the metal faceplate below.
    private var panelGroove: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.black.opacity(0.28)).frame(height: 1)
            Rectangle().fill(.white.opacity(0.55)).frame(height: 1)
        }
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
