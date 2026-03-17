import Foundation

@MainActor
class UndoRedoManager: ObservableObject {
    static let shared = UndoRedoManager()

    let undoManager = UndoManager()

    private init() {}
}
