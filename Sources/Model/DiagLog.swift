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

    // MARK: - Persistent breadcrumbs (survive a crash / abort)

    /// File of step markers, fsync'd after every write so the last step reached
    /// is on disk even if the next step aborts the process (e.g. an AVAudioEngine
    /// C++ assertion, which @try/@catch can't trap). Read back on next launch.
    private var breadcrumbURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("auseq-breadcrumbs.txt")
    }

    /// Start a fresh breadcrumb trace (call at the top of a risky operation).
    func beginBreadcrumbs(_ title: String) {
        try? "=== \(title) ===\n".write(to: breadcrumbURL, atomically: true, encoding: .utf8)
    }

    func breadcrumb(_ message: String) {
        log("crumb", message)
        let line = message + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: breadcrumbURL) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.synchronize()   // fsync — guarantee it hits disk before the next step
            try? h.close()
        } else {
            try? line.write(to: breadcrumbURL, atomically: true, encoding: .utf8)
        }
    }

    /// The last recorded trace (shown in Diagnostics so David can read it back
    /// after a crash + relaunch).
    var lastBreadcrumbs: String {
        (try? String(contentsOf: breadcrumbURL, encoding: .utf8)) ?? "(no trace recorded yet)"
    }

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

/// Persistent, fsync'd step marker — survives an abort/crash.
@MainActor func crumb(_ message: String) {
    DiagLog.shared.breadcrumb(message)
}
