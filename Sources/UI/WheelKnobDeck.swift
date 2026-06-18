import SwiftUI
import AudioToolbox

/// The AstroLab "screen + knobs" deck: the big nav-wheel flanked by four inlaid
/// parameter knobs on each side (the selected instrument's first 8 params),
/// milled into the wood. Used on iPad; the phone shows just the wheel.
struct WheelKnobDeck: View {
    @ObservedObject var model: AppModel
    var tone: WoodTone
    var wheelSize: CGFloat
    var knobSize: CGFloat = 64   // scaled up
    /// Vertical space the wheel row reserves — the wheel can be larger than this
    /// and overflow into the (empty) centre of the strip/transport above & below,
    /// so a bigger screen doesn't grow the wood panel.
    var reservedHeight: CGFloat = 128

    private var spacing: CGFloat { 24 }

    var body: some View {
        if let au = model.selectedAU {
            BoundKnobDeck(au: au, model: model, tone: tone, wheelSize: wheelSize,
                          knobSize: knobSize, spacing: spacing, reservedHeight: reservedHeight)
                // Rebuild the param VM when the AU instance changes — i.e. on track
                // change AND when a different plugin is loaded onto the same track.
                .id(ObjectIdentifier(au))
        } else {
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<4, id: \.self) { _ in emptyWell }
                SoundBrowserWheel(model: model, size: wheelSize).frame(height: reservedHeight)
                ForEach(4..<8, id: \.self) { _ in emptyWell }
            }
        }
    }

    private var emptyWell: some View {
        Circle().fill(.clear)
            .frame(width: knobSize, height: knobSize)
            .knobInlay(size: knobSize + 16, tone: tone)
            .opacity(0.55)
    }
}

/// What a knob is currently adjusting — shown on the center screen while turning.
struct KnobEdit: Equatable { var label: String; var value: String; var progress: Double }

/// Owns a parameter VM for the current AU and lays out left-4 / wheel / right-4.
private struct BoundKnobDeck: View {
    @StateObject private var vm: ParameterListVM
    @ObservedObject var model: AppModel
    let tone: WoodTone
    let wheelSize: CGFloat
    let knobSize: CGFloat
    let spacing: CGFloat
    let reservedHeight: CGFloat

    @State private var editing: KnobEdit?

    init(au: AUAudioUnit, model: AppModel, tone: WoodTone, wheelSize: CGFloat, knobSize: CGFloat, spacing: CGFloat, reservedHeight: CGFloat) {
        _vm = StateObject(wrappedValue: ParameterListVM(au: au))
        self.model = model; self.tone = tone; self.wheelSize = wheelSize; self.knobSize = knobSize
        self.spacing = spacing; self.reservedHeight = reservedHeight
    }

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<4, id: \.self) { knob($0) }
            centerScreen
            ForEach(4..<8, id: \.self) { knob($0) }
        }
        .animation(.easeOut(duration: 0.12), value: editing)
        .animation(.easeOut(duration: 0.15), value: model.presetFlash)
    }

    /// The big screen: shows the instrument browser normally, and the live param
    /// name + value while a knob is being turned.
    private var centerScreen: some View {
        ZStack {
            SoundBrowserWheel(model: model, size: wheelSize)
            if let editing {
                NavWheel(title: editing.label, subtitle: editing.value, glyph: "dial.medium.fill",
                         lit: true, size: wheelSize, progress: editing.progress)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else if let preset = model.presetFlash {
                NavWheel(title: preset, subtitle: "preset", glyph: "music.note.list",
                         lit: true, size: wheelSize, progress: 1)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(height: reservedHeight)   // bigger wheel overflows without growing the panel
    }

    @ViewBuilder private func knob(_ i: Int) -> some View {
        let idx = model.paramBank * AppModel.encoderCount + i   // current bank's params
        if idx < vm.parameters.count {
            InlaidKnob(vm: vm, param: vm.parameters[idx], tone: tone, size: knobSize, editing: $editing)
        } else {
            Circle().fill(.clear)
                .frame(width: knobSize, height: knobSize)
                .knobInlay(size: knobSize + 16, tone: tone)
                .opacity(0.55)
        }
    }
}

/// One param knob set into a light metal mount (bored into the wood), with a
/// small engraved label. Reports its name+value to the center screen while turning.
private struct InlaidKnob: View {
    @ObservedObject var vm: ParameterListVM
    let param: AUParameter
    let tone: WoodTone
    var size: CGFloat = 54
    @Binding var editing: KnobEdit?

    private var bipolar: Bool { param.minValue < 0 && param.maxValue > 0 }
    private var norm: Double {
        let span = Double(param.maxValue - param.minValue)
        return span > 0 ? Double(vm.value(param) - param.minValue) / span : 0
    }
    private var current: KnobEdit { KnobEdit(label: param.displayName, value: vm.formattedValue(param), progress: norm) }

    var body: some View {
        VStack(spacing: 3) {
            LEDRingKnob(value: norm, size: size, bipolar: bipolar,
                        onEditing: { active in editing = active ? current : nil }) { nv in
                let val = param.minValue + Float(nv) * (param.maxValue - param.minValue)
                vm.setDiscrete(val, param)
                if editing != nil { editing = current }   // keep the screen value live
            }
            .knobInlay(size: size + 16, tone: tone)
            Text(param.displayName)
                .font(Theme.mono(8, .semibold))
                .foregroundStyle(tone.ink.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: size + 16)
        }
    }
}
