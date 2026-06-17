import SwiftUI
import AudioToolbox
import CoreAudioKit

/// Shows the selected track's AUv3: a preset picker, a button to open the
/// plugin's own native UI, and a generic list of its parameters (the same
/// parameters the KeyLab encoders will drive in M5).
struct ParameterListView: View {
    @StateObject private var vm: ParameterListVM
    @State private var showingPluginUI = false

    init(au: AUAudioUnit) {
        _vm = StateObject(wrappedValue: ParameterListVM(au: au))
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
                    LazyVStack(spacing: 4) {
                        ForEach(vm.parameters, id: \.address) { param in
                            ParameterRow(vm: vm, param: param)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
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
}

private struct ParameterRow: View {
    @ObservedObject var vm: ParameterListVM
    let param: AUParameter

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
                DispatchQueue.main.async { self?.objectWillChange.send() }
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
