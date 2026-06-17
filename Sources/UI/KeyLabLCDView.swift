import SwiftUI

/// Experimental KeyLab LCD tester (M5). Sends a Mackie-Control display SysEx
/// (`F0 00 00 66 <id> 12 <offset> <text> F7`) to the DAW port so we can find
/// the device-ID/format the mkII actually renders, before auto-pushing param
/// names to the screen. The KeyLab must be in a DAW/Mackie mode.
struct KeyLabLCDView: View {
    @ObservedObject var midi: MIDIManager

    @State private var text = "AUSEQ"
    @State private var deviceID = 0x14          // 0x14 Mackie Control, 0x10 Logic Control
    @State private var line = 0
    @State private var port = "DAW"
    @State private var lastHex = ""
    @State private var sentOK: Bool?

    private let deviceIDs = [0x10, 0x11, 0x12, 0x13, 0x14, 0x15]

    var body: some View {
        Form {
            Section("Message") {
                TextField("Text", text: $text)
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                Picker("Device ID", selection: $deviceID) {
                    ForEach(deviceIDs, id: \.self) { Text(String(format: "0x%02X", $0)).tag($0) }
                }
                Picker("Line", selection: $line) { Text("Line 1").tag(0); Text("Line 2").tag(1) }
                Picker("Port", selection: $port) {
                    ForEach(midi.destinationNames, id: \.self) { name in
                        Text(shortPort(name)).tag(portKey(name))
                    }
                }
            }

            Section {
                Button("Send to LCD") { send(text) }
                Button("Clear LCD") { send(String(repeating: " ", count: 56)) }
                Button("Sweep device IDs") { sweep() }
            }

            if let sentOK {
                Section("Result") {
                    Label(sentOK ? "Sent" : "No destination matched “\(port)”",
                          systemImage: sentOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(sentOK ? .green : .orange)
                    if !lastHex.isEmpty {
                        Text(lastHex).font(.system(.footnote, design: .monospaced))
                    }
                }
            }

            Section("How to use") {
                Text("Type something, hit Send, and watch the KeyLab screen. If nothing shows, try another Device ID (0x14 = Mackie, 0x10 = Logic) or “Sweep device IDs”. Tell me which one lights up the screen.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("KeyLab LCD")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func mcuBytes(_ s: String, id: Int) -> [UInt8] {
        let offset: UInt8 = line == 0 ? 0 : 56
        var bytes: [UInt8] = [0xF0, 0x00, 0x00, 0x66, UInt8(id), 0x12, offset]
        bytes += s.unicodeScalars.prefix(56).map { UInt8($0.value & 0x7F) }
        bytes.append(0xF7)
        return bytes
    }

    private func send(_ s: String) {
        let bytes = mcuBytes(s, id: deviceID)
        sentOK = midi.send(bytes, toPortNamed: port)
        lastHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Fire the text at every candidate device ID so we can see which renders.
    private func sweep() {
        var ok = false
        for id in deviceIDs { ok = midi.send(mcuBytes(text, id: id), toPortNamed: port) || ok }
        sentOK = ok
        lastHex = "swept IDs " + deviceIDs.map { String(format: "0x%02X", $0) }.joined(separator: ", ")
    }

    private func portKey(_ name: String) -> String {
        name.localizedCaseInsensitiveContains("daw") ? "DAW" : name
    }

    private func shortPort(_ name: String) -> String {
        name.replacingOccurrences(of: "KeyLab mkII 88 ", with: "KL ")
            .replacingOccurrences(of: "Network Session 1", with: "Net")
    }
}
