import InvoiceCore
import Observation
import PDFKit
import SwiftUI
import UIKit

/// Renders a document to PDF and keeps the file for sharing, printing and saving
/// (`spec/pdf/RENDERING.md`, `spec/documents.md` §8).
@MainActor @Observable
final class DocumentPreviewViewModel: Identifiable {
    struct State: Equatable {
        var template: TemplateID
        var file: URL?
        var isRendering = false
        var errorMessage: String?
        /// Shown after sharing or printing an issued document that is not marked sent yet.
        var askToMarkSent = false
        var sentAt: Int64?
    }

    var state: State
    let id: String
    private let session: Session
    private var document: InvoiceCore.Document
    private let computed: ComputedDocument
    /// Tells the document screen the status changed.
    private let onSent: (Int64) -> Void
    /// Set only when opened from "Send reminder" (`spec/reminders.md` §4): shared alongside the PDF.
    let reminderMessage: String?

    init(session: Session, document: InvoiceCore.Document, computed: ComputedDocument,
         reminderMessage: String? = nil, onSent: @escaping (Int64) -> Void = { _ in }) {
        self.session = session
        self.document = document
        self.computed = computed
        self.reminderMessage = reminderMessage
        self.onSent = onSent
        id = document.id
        state = State(template: document.templateId, sentAt: document.sentAt)
    }

    var templates: [PDFTemplate] { session.pdfLibrary.allTemplates }
    var title: String { document.number ?? DocumentText.title(document, isPersisted: true) }
    var canMarkSent: Bool { !document.isDraft && state.sentAt == nil }

    func render() async {
        state.isRendering = true
        defer { state.isRendering = false }
        do {
            let file = try await session.pdfLibrary.file(for: document, business: session.business,
                                                          computed: computed, template: state.template)
            state.file = file.url
        } catch {
            state.errorMessage = "The PDF couldn't be created."
        }
    }

    func setTemplate(_ template: TemplateID) async {
        guard template != state.template else { return }
        state.template = template
        state.file = nil
        await render()
    }

    /// The share sheet or the printer finished: offer to mark the document as sent.
    func didShare() {
        if canMarkSent { state.askToMarkSent = true }
    }

    func markSent() async {
        do {
            let now = session.dependencies.time.now()
            try await session.dependencies.documents.markSent(documentID: document.id, at: now)
            state.sentAt = now
            document.sentAt = now
            onSent(now)
        } catch {
            state.errorMessage = "The \(DocumentText.noun(document.docType)) couldn't be marked as sent."
        }
    }

    func dismissError() { state.errorMessage = nil }
}

/// The preview screen: the rendered document, a template switcher and the share, print and save actions.
struct DocumentPreviewView: View {
    @Bindable var model: DocumentPreviewViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let file = model.state.file {
                    PDFPreview(url: file)
                        .ignoresSafeArea(edges: .bottom)
                        // iPad: drag the PDF straight into Mail, Files or another app.
                        .draggable(file) {
                            Label(model.title, systemImage: "doc.richtext")
                                .padding(Theme.Space.m)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                        }
                } else if model.state.isRendering {
                    ProgressView("Preparing the PDF…")
                } else {
                    ContentUnavailableView("No preview", systemImage: "doc.richtext",
                                           description: Text("The PDF couldn't be created."))
                }
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { templateSwitcher }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let file = model.state.file {
                        Button("Print", systemImage: "printer") { airPrint(file) }
                        Button("Share", systemImage: "square.and.arrow.up") { share(file) }
                            .accessibilityIdentifier("sharePDF")
                    }
                }
            }
            .task { await model.render() }
            .alert("Mark as sent?", isPresented: $model.state.askToMarkSent) {
                Button("Mark as sent") { Task { await model.markSent() } }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text("The status changes to Sent. You can still share it again.")
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { model.dismissError() }
            } message: {
                Text(model.state.errorMessage ?? "")
            }
        }
    }

    private var templateSwitcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Space.s) {
                ForEach(model.templates) { template in
                    Button {
                        Task { await model.setTemplate(template.id) }
                    } label: {
                        Text(template.label)
                            .font(.subheadline.weight(model.state.template == template.id ? .semibold : .regular))
                            .padding(.horizontal, Theme.Space.m)
                            .padding(.vertical, Theme.Space.s)
                            .background(model.state.template == template.id ? Theme.brand.opacity(0.14)
                                                                            : Theme.surfaceMuted,
                                        in: Capsule())
                    }
                    .accessibilityIdentifier("template-\(template.id.rawValue)")
                    .accessibilityAddTraits(model.state.template == template.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
    }

    /// The share sheet (WhatsApp, Mail, Save to Files, …). `UIActivityViewController` rather than `ShareLink`
    /// because only its completion handler tells us whether the document was really sent, and the "Mark as sent?"
    /// prompt must not appear when the sheet was cancelled.
    private func share(_ url: URL) {
        guard let window = Self.keyWindow, let presenter = Self.topViewController else { return }
        var items: [Any] = []
        if let message = model.reminderMessage { items.append(message) }
        items.append(url)
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            if completed { model.didShare() }
        }
        anchor(controller.popoverPresentationController, in: window)
        presenter.present(controller, animated: true)
    }

    /// AirPrint. `present(from:in:)` works on both iPhone and iPad, unlike the plain `present(animated:)`.
    private func airPrint(_ url: URL) {
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = model.title
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = url
        guard let window = Self.keyWindow else { return }
        controller.present(from: CGRect(x: window.bounds.maxX - 60, y: 60, width: 1, height: 1),
                           in: window, animated: true) { _, completed, _ in
            if completed { model.didShare() }
        }
    }

    /// Popovers on iPad need a source; the toolbar buttons sit at the top right.
    private func anchor(_ popover: UIPopoverPresentationController?, in window: UIWindow) {
        popover?.sourceView = window
        popover?.sourceRect = CGRect(x: window.bounds.maxX - 60, y: 60, width: 1, height: 1)
        popover?.permittedArrowDirections = .up
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }

    /// The preview is itself a sheet, so present from whatever is on top of it.
    private static var topViewController: UIViewController? {
        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

/// A PDF file shown with PDFKit.
struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            view.goToFirstPage(nil)
        }
    }
}

/// The same preview inside the iPad builder's right pane, rendered from the draft as it is edited.
struct DocumentPreviewPane: View {
    let session: Session
    let document: InvoiceCore.Document
    let computed: ComputedDocument?
    @State private var data: Data?
    @State private var isRendering = false

    var body: some View {
        Group {
            if let data, let pdf = PDFDocument(data: data) {
                PDFDataPreview(document: pdf)
            } else if computed == nil {
                ContentUnavailableView("No preview yet", systemImage: "doc.richtext",
                                       description: Text("Fix the highlighted problems to see the document."))
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .topTrailing) {
            if isRendering { ProgressView().padding(Theme.Space.s) }
        }
        .task(id: renderKey) { await render() }
    }

    /// Re-renders when anything that shows on the page changes; typing pauses first (400 ms).
    private var renderKey: String {
        "\(document.updatedAt)-\(document.lines.count)-\(computed?.totals.total ?? 0)-\(document.templateId.rawValue)"
            + "-\(document.currency.rawValue)-\(document.buyerSnapshot?.name ?? "")"
    }

    private func render() async {
        guard let computed else { return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        isRendering = true
        defer { isRendering = false }
        data = try? await session.pdfLibrary.data(for: document, business: session.business, computed: computed)
    }
}

/// A PDF held in memory (the live preview), shown with PDFKit.
struct PDFDataPreview: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        let page = view.currentPage.flatMap { view.document?.index(for: $0) }
        view.document = document
        if let page, let restored = document.page(at: min(page, document.pageCount - 1)) {
            view.go(to: restored)
        }
    }
}
