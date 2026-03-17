import Foundation
import Combine

struct ConsoleEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: ConsoleLevel
    let scriptName: String
    let message: String

    enum ConsoleLevel: String {
        case log, warn, error
    }
}

final class ScriptConsoleManager: ObservableObject {
    static let shared = ScriptConsoleManager()

    @Published private(set) var entries: [ConsoleEntry] = []

    private let maxEntries = 500

    private init() {}

    func log(_ message: String, from scriptName: String, level: ConsoleEntry.ConsoleLevel = .log) {
        let entry = ConsoleEntry(timestamp: Date(), level: level, scriptName: scriptName, message: message)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
    }
}
