import Foundation
import Combine

/// App-wide diagnostics log. Subsystems write timestamped events here; the
/// Configuration → Diagnostics screen shows them live and can Share/AirDrop the
/// whole log back for debugging things Claude can't observe directly.
@MainActor
final class DiagLog: ObservableObject {
    static let shared = DiagLog()

    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        let category: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []
    private let cap = 800

    func log(_ category: String, _ message: String) {
        entries.append(Entry(time: Date(), category: category, message: message))
        if entries.count > cap { entries.removeFirst(entries.count - cap) }
    }

    func clear() { entries.removeAll() }

    var text: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let header = "AUSeq Diagnostics — \(entries.count) events"
        let lines = entries.map { "\(f.string(from: $0.time))  [\($0.category)]  \($0.message)" }
        return ([header] + lines).joined(separator: "\n")
    }
}

/// Convenience for one-liners anywhere on the main actor.
@MainActor func diag(_ category: String, _ message: String) {
    DiagLog.shared.log(category, message)
}
