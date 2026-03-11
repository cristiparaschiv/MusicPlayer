import SwiftUI
import AppKit

struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 13)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchTextField

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let searchField = obj.object as? NSSearchField else { return }
            parent.text = searchField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.text = ""
                (control as? NSSearchField)?.stringValue = ""
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
    }
}
