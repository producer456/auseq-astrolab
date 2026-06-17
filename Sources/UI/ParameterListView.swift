import SwiftUI
import AudioToolbox
import CoreAudioKit

/// Shows the selected track's AUv3: a preset picker, a button to open the
/// plugin's own native UI, and a generic list of its parameters (the same
/// parameters the KeyLab encoders will drive in M5).
struct ParameterListView: View {
    @StateObject private var vm: ParameterListVM
    @ObservedObject var model: AppModel
    @State private var showingPluginUI = false

    init(au: AUAudioUnit, model: AppModel) {
        _vm = StateObject(wrappedValue: ParameterListVM(au: au))
        self.model = model
    }

    /// Encoder badge ("E1"…"E9") for a parameter at `index`, if it's in the
    /// page of params the KeyLab encoders currently drive.
    private func encoderLabel(_ index: Int) -> String? {
        let base = model.paramBank * AppModel.encoderCount
        guard index >= base, index < base + AppModel.encoderCount else { return nil }
        return "E\(index - base + 1)"
    }

    /// Only the current page of parameters — one per physical encoder, so the
    /// screen mirrors the controller 1:1. Keeps each param's original index for
    /// the encoder badge.
    private var bankParams: [(offset: Int, element: AUParameter)] {
        let base = model.paramBank * AppModel.encoderCount
        return vm.parameters.enumerated()
            .filter { $0.offset >= base && $0.offset < base + AppModel.encoderCount }
            .map { (offset: $0.offset, element: $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.1))
            if vm.parameters.isEmpty {
                Spacer()
                Text("This plugin exposes no host-readable parameters. Use “Plugin UI”.")
                    .etchedLabel(11, soft: true, weight: .medium).tracking(0.5)
                    .multilineTextAlignment(.center).padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 14)], spacing: 20) {
                        ForEach(bankParams, id: \.offset) { item in
                            ParameterKnob(vm: vm, param: item.element, encoderLabel: encoderLabel(item.offset))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 18)
                }
            }
        }
        .sheet(isPresented: $showingPluginUI) {
            NavigationStack {
                AUPluginUIView(au: vm.au)
                    .ignoresSafeArea()
                    .navigationTitle("Plugin")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingPluginUI = false } } }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if vm.presets.isEmpty {
                Text("No factory presets").etchedLabel(10, soft: true, weight: .medium)
            } else {
                Menu {
                    ForEach(vm.presets, id: \.number) { preset in
                        Button {
                            vm.applyPreset(preset)
                        } label: {
                            if preset.number == vm.currentPresetNumber {
                                Label(preset.name, systemImage: "checkmark")
                            } else {
                                Text(preset.name)
                            }
                        }
                    }
                } label: {
                    Label(vm.currentPresetName, systemImage: "slider.horizontal.below.square.filled.and.square")
                        .font(Theme.mono(12, .semibold))
                        .foregroundStyle(Theme.etched)
                }
            }
            Spacer()
            if model.paramCount > 0 { bankNav }
            Button {
                showingPluginUI = true
            } label: {
                Label("Plugin UI", systemImage: "rectangle.inset.filled")
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.orange)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.rail)
    }

    @ViewBuilder
    private var bankNav: some View {
        let base = model.paramBank * AppModel.encoderCount + 1
        let end = min(model.paramCount, base + AppModel.encoderCount - 1)
        HStack(spacing: 8) {
            Button { model.pageBank(-1) } label: { Image(systemName: "chevron.left.circle.fill") }
                .disabled(model.paramBank == 0)
            Text("ENC \(base)–\(end)/\(model.paramCount)")
                .font(Theme.mono(10, .semibold))
            Button { model.pageBank(1) } label: { Image(systemName: "chevron.right.circle.fill") }
                .disabled(model.paramBank >= model.bankCount - 1)
        }
        .foregroundStyle(Theme.orange)
        .padding(.trailing, 8)
    }
}

/// AstroLab-style parameter knob: LED-ring fill mirrors the value (bipolar params
/// light from center), with the name + value below and the encoder badge.
private struct ParameterKnob: View {
    @ObservedObject var vm: ParameterListVM
    let param: AUParameter
    var encoderLabel: String? = nil

    private var options: [String]? {
        guard param.unit == .indexed, let s = param.valueStrings, s.count > 1 else { return nil }
        return s
    }
    private var isBoolean: Bool { param.unit == .boolean }
    private var bipolar: Bool { param.minValue < 0 && param.maxValue > 0 }
    private var norm: Double {
        let span = Double(param.maxValue - param.minValue)
        return span > 0 ? Double(vm.value(param) - param.minValue) / span : 0
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                control
                if let encoderLabel {
                    Text(encoderLabel).font(Theme.mono(7, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.orange))
                        .offset(x: 4, y: -2)
                }
            }
            Text(param.displayName).etchedLabel(8, weight: .semibold)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(vm.formattedValue(param)).font(Theme.mono(8, .medium))
                .foregroundStyle(Theme.orange).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var control: some View {
        if isBoolean {
            let on = vm.value(param) > 0.5
            Button {
                vm.setDiscrete(on ? param.minValue : param.maxValue, param)
            } label: {
                ZStack {
                    Circle().stroke(Color.black.opacity(0.08), lineWidth: 3).frame(width: 50, height: 50)
                    Circle().fill(on ? Theme.orange : Color(white: 0.93)).frame(width: 38, height: 38)
                        .overlay(Circle().stroke(.black.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: on ? Theme.orange.opacity(0.6) : .black.opacity(0.1), radius: 3)
                    Image(systemName: "power").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(on ? .white : Theme.etchedSoft)
                }
                .frame(width: 60, height: 60)
            }
            .buttonStyle(.plain)
        } else if let options {
            LEDRingKnob(value: norm, size: 54) { nv in
                let idx = Int((nv * Double(options.count - 1)).rounded())
                vm.setDiscrete(Float(idx), param)
            }
        } else {
            LEDRingKnob(value: norm, size: 54, bipolar: bipolar) { nv in
                let val = param.minValue + Float(nv) * (param.maxValue - param.minValue)
                vm.setDiscrete(val, param)
            }
        }
    }
}

private struct ParameterRow: View {
    @ObservedObject var vm: ParameterListVM
    let param: AUParameter
    var encoderLabel: String? = nil

    /// Enum/stepped option names, when the parameter is genuinely indexed.
    private var options: [String]? {
        guard param.unit == .indexed, let s = param.valueStrings, s.count > 1 else { return nil }
        return s
    }

    private var currentIndex: Int {
        let count = options?.count ?? 1
        return max(0, min(count - 1, Int(vm.value(param).rounded())))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let encoderLabel {
                    Text(encoderLabel)
                        .font(Theme.mono(8, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.orange))
                }
                Text(param.displayName).etchedLabel(10, weight: .semibold).tracking(0.6).lineLimit(1)
                Spacer()
                trailing
            }
            if isStepped {
                // Snap to whole steps so the slider can land EXACTLY on the
                // minimum (off). Continuous sliders almost never hit exact-min,
                // and many plugins treat any value > min as "on" — so a smooth
                // slider turns the param on but can't turn it back off.
                Slider(
                    value: Binding(get: { vm.value(param) }, set: { vm.setDiscrete($0, param) }),
                    in: param.minValue...param.maxValue,
                    step: 1
                )
            } else if isContinuous {
                Slider(
                    value: Binding(get: { vm.value(param) }, set: { vm.setValue($0, param) }),
                    in: param.minValue...param.maxValue
                )
            }
        }
        .padding(.vertical, 2)
    }

    /// Discrete numeric param (e.g. an indexed/enum value with no value strings).
    /// Booleans and string-enum params are handled by `trailing` (toggle/menu).
    private var isStepped: Bool {
        param.unit == .indexed && options == nil
            && param.maxValue > param.minValue
    }

    @ViewBuilder
    private var trailing: some View {
        if param.unit == .boolean {
            Toggle("", isOn: Binding(
                get: { vm.value(param) > 0.5 },
                set: { vm.setDiscrete($0 ? param.maxValue : param.minValue, param) }
            ))
            .labelsHidden()
        } else if let options {
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, name in
                    Button { vm.setDiscrete(Float(idx), param) } label: {
                        if idx == currentIndex { Label(name, systemImage: "checkmark") }
                        else { Text(name) }
                    }
                }
            } label: {
                Text(options[currentIndex]).font(Theme.mono(10)).foregroundStyle(Theme.orange)
            }
        } else {
            Text(vm.formattedValue(param)).font(Theme.mono(10)).foregroundStyle(Theme.etchedSoft)
        }
    }

    private var isContinuous: Bool {
        param.unit != .boolean && param.unit != .indexed
            && options == nil && param.maxValue > param.minValue
    }
}

@MainActor
final class ParameterListVM: ObservableObject {
    let au: AUAudioUnit
    @Published private(set) var parameters: [AUParameter]
    @Published private(set) var presets: [AUAudioUnitPreset]
    @Published private(set) var currentPresetNumber: Int

    private var observerToken: AUParameterObserverToken?

    init(au: AUAudioUnit) {
        self.au = au
        self.parameters = au.parameterTree?.allParameters ?? []
        self.presets = au.factoryPresets ?? []
        self.currentPresetNumber = au.currentPreset?.number ?? -1

        if let tree = au.parameterTree {
            observerToken = tree.token(byAddingParameterObserver: { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    // Keep the preset menu's checkmark in sync when the preset is
                    // changed from hardware (which moves parameters).
                    self.currentPresetNumber = self.au.currentPreset?.number ?? -1
                    self.objectWillChange.send()
                }
            })
        }
    }

    deinit {
        if let observerToken, let tree = au.parameterTree {
            tree.removeParameterObserver(observerToken)
        }
    }

    var currentPresetName: String {
        au.currentPreset?.name ?? "Presets"
    }

    func value(_ param: AUParameter) -> Float { param.value }

    func setValue(_ value: Float, _ param: AUParameter) {
        param.setValue(value, originator: observerToken)
    }

    /// For toggles/menus: set the value and refresh immediately. Our own writes
    /// are suppressed from the parameter observer (to avoid echo), so without
    /// this the control wouldn't reflect the new state until something else
    /// moved the parameter.
    func setDiscrete(_ value: Float, _ param: AUParameter) {
        param.setValue(value, originator: observerToken)
        objectWillChange.send()
    }

    func formattedValue(_ param: AUParameter) -> String {
        param.string(fromValue: nil)
    }

    func applyPreset(_ preset: AUAudioUnitPreset) {
        au.currentPreset = preset
        currentPresetNumber = preset.number
        // Preset changes can move every parameter; refresh the views.
        objectWillChange.send()
    }
}
