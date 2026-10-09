import InvoiceCore
import SwiftUI
import UIKit

/// Settings → Backup (`spec/backup.md` §2, §4, §5).
struct BackupPage: View {
    let session: Session
    @State private var model: BackupViewModel

    init(session: Session) {
        self.session = session
        _model = State(initialValue: BackupViewModel(dependencies: session.dependencies, deviceID: session.deviceID) {
            [weak session] in
            guard let session else { return }
            await session.pdfLibrary.forgetAll()
            await session.reloadApp()
        })
    }

    var body: some View {
        @Bindable var router = session.router.settings
        Form {
            Section {
                Label {
                    Text(model.lastBackupText)
                } icon: {
                    Image(systemName: model.isDue ? "exclamationmark.triangle.fill" : "checkmark.circle")
                        .foregroundStyle(model.isDue ? Color.orange : Color.secondary)
                }
                .accessibilityIdentifier("backup.last")
                Button {
                    Task { await model.saveToFiles() }
                } label: {
                    Label("Save backup to Files", systemImage: "folder")
                }
                .accessibilityIdentifier("backup.saveToFiles")
                Button {
                    Task {
                        guard let export = await model.prepareExport() else { return }
                        SystemSheets.share([export.url]) { completed in
                            Task { await model.exportFinished(completed: completed) }
                        }
                    }
                } label: {
                    Label("Share backup…", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Back up")
            } footer: {
                Text(model.isDue
                     ? "You haven't backed up in a while. Save a backup somewhere other than this device."
                     : "One file with your business, clients, items, invoices, quotes and payments. Keep it somewhere safe, such as iCloud Drive or your email.")
            }
            Section {
                Button(role: .destructive) {
                    model.state.showsImporter = true
                } label: {
                    Label("Restore from a backup…", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("backup.restore")
            } header: {
                Text("Restore")
            } footer: {
                Text("Replaces all the data on this device with the backup. A copy of the current data is kept first.")
            }
        }
        .disabled(model.state.isWorking)
        .overlay { if model.state.isWorking { ProgressView() } }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .backupFlows(model: model)
        .task { await model.observe() }
        .task(id: router.incomingBackup) {
            guard let url = router.incomingBackup else { return }
            router.incomingBackup = nil
            await model.open(url)
        }
    }
}

/// The exporter, importer, confirmation and error presentation, shared by Settings and onboarding.
struct BackupFlows: ViewModifier {
    @Bindable var model: BackupViewModel

    func body(content: Content) -> some View {
        content
            .fileExporter(isPresented: $model.state.showsExporter, document: model.state.export?.document,
                          contentType: .invoiceBackup, defaultFilename: model.state.export?.fileName) { result in
                Task { await model.exportFinished(completed: (try? result.get()) != nil) }
            }
            .fileImporter(isPresented: $model.state.showsImporter, allowedContentTypes: [.invoiceBackup, .json]) {
                result in
                Task { await model.importFinished(result) }
            }
            .sheet(item: $model.state.pendingRestore) { pending in
                RestoreConfirmationView(preview: pending.preview, isWorking: model.state.isWorking,
                                        cancel: model.cancelRestore,
                                        confirm: { Task { await model.confirmRestore() } })
            }
            .alert("Backup", isPresented: errorBinding) {
                Button("OK", role: .cancel) { model.dismissError() }
            } message: {
                Text(model.state.errorMessage ?? "")
            }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.state.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
    }
}

extension View {
    func backupFlows(model: BackupViewModel) -> some View {
        modifier(BackupFlows(model: model))
    }
}

/// §4 step 2: what the backup holds and what restoring does, before anything changes.
struct RestoreConfirmationView: View {
    let preview: BackupPreview
    let isWorking: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Made", value: Self.date(preview.file.createdAt))
                    LabeledContent("On", value: preview.file.app.platform == "android" ? "Android" : "iPhone or iPad")
                } header: {
                    Text("This backup")
                }
                Section("It contains") {
                    row("Businesses", preview.live.businesses)
                    row("Clients", preview.live.clients)
                    row("Items", preview.live.catalogItems)
                    row("Invoices and quotes", preview.live.documents)
                    row("Payments", preview.live.payments)
                }
                Section {
                    Button(role: .destructive, action: confirm) {
                        Text("Replace all data")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("backup.confirmRestore")
                } footer: {
                    Text("Everything on this device is replaced by the backup. A copy of the current data is kept on this device first.")
                }
            }
            .navigationTitle("Restore backup?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
            }
            .overlay { if isWorking { ProgressView() } }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func row(_ title: String, _ count: Int) -> some View {
        LabeledContent(title, value: "\(count)")
    }

    private static func date(_ millis: Int64) -> String {
        Date(timeIntervalSince1970: Double(millis) / 1000).formatted(date: .abbreviated, time: .shortened)
    }
}

/// UIKit sheets SwiftUI has no completion handler for.
@MainActor
enum SystemSheets {
    /// The share sheet; `completion(true)` only when the user really sent or saved the items.
    static func share(_ items: [Any], completion: @escaping @MainActor (Bool) -> Void) {
        guard let window = keyWindow, let presenter = topViewController else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            MainActor.assumeIsolated { completion(completed) }
        }
        controller.popoverPresentationController?.sourceView = window
        controller.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY,
                                                                      width: 1, height: 1)
        controller.popoverPresentationController?.permittedArrowDirections = []
        presenter.present(controller, animated: true)
    }

    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    }

    static var topViewController: UIViewController? {
        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

/// A backup file dropped onto Settings, copied out of the drag session before it ends.
struct DroppedBackup: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .invoiceBackup) { received in
            DroppedBackup(url: try copy(received.file))
        }
        FileRepresentation(importedContentType: .json) { received in
            DroppedBackup(url: try copy(received.file))
        }
    }

    private static func copy(_ file: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Dropped")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: "\(UUID().uuidString.lowercased())-\(file.lastPathComponent)")
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }
}
