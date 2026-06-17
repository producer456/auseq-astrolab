import SwiftUI
import AVFoundation

struct TrackListView: View {
    @ObservedObject var model: AppModel
    @State private var assigningTrack: Track?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tracks").etchedLabel(13, weight: .bold)
                Spacer()
                Button {
                    model.addTrack()
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.orange)
                }
            }
            .padding(.horizontal).padding(.vertical, 10)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.tracks) { track in
                        TrackRow(
                            track: track,
                            isSelected: track.id == model.selectedTrackID,
                            isLoading: model.audio.loadingTrackIDs.contains(track.id),
                            onSelect: { model.select(track) },
                            onAssign: { assigningTrack = track },
                            onMute: { model.toggleMute(track) },
                            onVolume: { model.setVolume($0, for: track) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .sheet(item: $assigningTrack) { track in
            InstrumentPicker(browser: model.browser) { component in
                model.assignInstrument(component, to: track)
                assigningTrack = nil
            }
        }
    }
}

private struct TrackRow: View {
    @ObservedObject var track: Track
    let isSelected: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    let onAssign: () -> Void
    let onMute: () -> Void
    let onVolume: (Float) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(track.color).frame(width: 6, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.etched)
                    Text(track.instrumentName).etchedLabel(9, soft: true, weight: .medium).lineLimit(1)
                }
                Spacer()
                if isLoading { ProgressView() }
                AmberLED(on: isSelected)
                Button(action: onMute) {
                    Image(systemName: track.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(track.muted ? Theme.orange : Theme.etchedSoft)
                }
                Button(action: onAssign) {
                    Image(systemName: "pianokeys").foregroundStyle(Theme.orange)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(Theme.etchedSoft)
                Slider(value: Binding(get: { track.volume }, set: { onVolume($0) }), in: 0...1)
            }
        }
        .padding(10)
        .metalCard(selected: isSelected)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

struct InstrumentPicker: View {
    @ObservedObject var browser: AUComponentBrowser
    let onSelect: (AVAudioUnitComponent) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if browser.instruments.isEmpty {
                    Text("No AUv3 instruments found. Install instrument apps from the App Store, then tap Rescan.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(browser.instruments, id: \.self) { comp in
                        Button {
                            onSelect(comp)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(comp.name).foregroundStyle(.primary)
                                Text(comp.manufacturerName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Instrument")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Rescan") { browser.refresh() } }
            }
        }
    }
}
