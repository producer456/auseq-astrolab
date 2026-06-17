import SwiftUI

/// Compact vertical track selector — a thin rail of color-coded numbered chips
/// (replaces the wide sidebar list). Tap a chip to select; tap the already-
/// selected chip again to open the full per-track controls (`onExpand`).
struct TrackRail: View {
    @ObservedObject var model: AppModel
    var onExpand: () -> Void

    static let width: CGFloat = 58

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(Array(model.tracks.enumerated()), id: \.element.id) { idx, track in
                        TrackRailChip(track: track, index: idx,
                                      selected: track.id == model.selectedTrackID) {
                            if track.id == model.selectedTrackID { onExpand() }
                            else { model.select(track) }
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            Button { model.addTrack() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 42, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.3)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.gold.opacity(0.5)))
            }
            .padding(.bottom, 12)
        }
        .frame(width: Self.width)
        .background(Theme.rail)
    }
}

/// One rail chip — observes its Track so arm/instrument dots stay live.
private struct TrackRailChip: View {
    @ObservedObject var track: Track
    let index: Int
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("\(index + 1)")
                .font(Theme.mono(16, .bold))
                .foregroundStyle(selected ? .white : Theme.etched)
            HStack(spacing: 4) {
                // armed = record dot; instrument loaded = filled color dot
                Circle().fill(track.armed ? Theme.orange : Theme.etchedSoft.opacity(0.25))
                    .frame(width: 5, height: 5)
                Circle().fill(track.hasInstrument ? track.color : Theme.etchedSoft.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 46, height: 46)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? track.color.opacity(0.28) : Color.white.opacity(0.28))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(track.color)
                .frame(width: 4, height: 30).padding(.leading, 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? track.color : Theme.gold.opacity(0.4), lineWidth: selected ? 2 : 1)
        )
        .shadow(color: selected ? track.color.opacity(0.5) : .clear, radius: 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
