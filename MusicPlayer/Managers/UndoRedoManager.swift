import Foundation

@MainActor
class UndoRedoManager {
    static let shared = UndoRedoManager()

    let undoManager = UndoManager()

    private init() {}
}
