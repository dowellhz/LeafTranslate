import Cocoa

final class ShortcutTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch key {
        case "a":
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            currentEditor()?.selectAll(nil)
            return true
        case "c":
            return copySelectionToClipboard() || super.performKeyEquivalent(with: event)
        case "x":
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            if copySelectionToClipboard() {
                currentEditor()?.delete(nil)
                return true
            }
            return super.performKeyEquivalent(with: event)
        case "v":
            guard event.modifierFlags.contains(.command) else {
                return super.performKeyEquivalent(with: event)
            }
            pasteClipboard()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private func copySelectionToClipboard() -> Bool {
        guard let editor = currentEditor() else { return false }
        let selectedRange = editor.selectedRange
        guard selectedRange.length > 0,
              let range = Range(selectedRange, in: editor.string) else {
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(editor.string[range]), forType: .string)
        return true
    }

    private func pasteClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if let editor = currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: text)
        } else {
            stringValue += text
        }
    }
}

final class ShortcutSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        if (event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)), key == "v" {
            pasteClipboard()
            return true
        }
        if event.modifierFlags.contains(.command), key == "a" {
            currentEditor()?.selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func pasteClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if let editor = currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: text)
        } else {
            stringValue += text
        }
    }
}
