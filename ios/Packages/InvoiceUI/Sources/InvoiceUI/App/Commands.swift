import InvoiceCore
import SwiftUI

extension FocusedValues {
    /// The signed-in session of the focused window.
    @Entry var session: Session?
    /// The document open in the focused window.
    @Entry var documentEditor: DocumentViewModel?
}

/// Menu-bar commands and hardware-keyboard shortcuts (ADR-0014): ⌘N new invoice, ⇧⌘N new quote, ⌘D duplicate
/// the selected line, ⌘P preview and share, ⌘F find invoices. ⌘↩ (issue) sits on the builder's Issue button.
public struct InvoiceCommands: Commands {
    @FocusedValue(\.session) private var session
    @FocusedValue(\.documentEditor) private var editor

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Invoice") { session?.startNewDocument(.invoice) }
                .keyboardShortcut("n")
                .disabled(session == nil)
            Button("New Quote") { session?.startNewDocument(.quote) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(session == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Find Invoices…") {
                guard let session else { return }
                session.router.selectedTab = .documents
                session.router.documents.isSearchFocused = true
            }
            .keyboardShortcut("f")
            .disabled(session == nil)
        }
        CommandMenu("Document") {
            Button("Add Line") { editor?.addLine() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(editor?.isDraft != true)
            Button("Duplicate Line") { editor?.duplicateSelectedLine() }
                .keyboardShortcut("d")
                .disabled(editor?.canDuplicateSelectedLine != true)
            Divider()
            Button("Preview & Share…") { Task { await editor?.openPreview() } }
                .keyboardShortcut("p")
                .disabled(editor?.canPreview != true)
        }
    }
}
