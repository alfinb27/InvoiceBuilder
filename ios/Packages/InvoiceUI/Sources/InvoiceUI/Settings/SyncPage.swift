import InvoiceCore
import Observation
import SwiftUI

/// Settings → iCloud sync (`spec/sync.md` §2).
@MainActor @Observable
final class SyncViewModel {
    var status: SyncStatus = .unavailable
    var isWorking = false
    var errorMessage: String?

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func observe() async {
        for await status in dependencies.sync.observeStatus() { self.status = status }
    }

    var isAvailable: Bool { status != .unavailable }
    var isOn: Bool { status != .off && status != .unavailable }

    func setOn(_ on: Bool) async {
        isWorking = true
        defer { isWorking = false }
        await dependencies.sync.setEnabled(on)
    }

    func syncNow() async {
        isWorking = true
        defer { isWorking = false }
        await dependencies.sync.syncNow()
    }

    /// §2: a safety snapshot, then erase and start again with the signed-in account.
    func eraseAndResume() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await dependencies.backup.writeSafetySnapshot()
            try await dependencies.sync.eraseLocalDataAndResume()
        } catch {
            errorMessage = "Sync couldn't start again. Nothing was erased unless iCloud had already finished."
        }
    }

    var statusText: String {
        switch status {
        case .off: "Off on this device"
        case .upToDate: "Up to date"
        case .syncing: "Syncing…"
        case .paused(.signedOut): "Paused: not signed in to iCloud"
        case .paused(.accountChanged): "Paused: a different iCloud account is signed in"
        case .paused(.quotaExceeded): "Paused: iCloud storage is full"
        case .paused(.networkUnavailable): "Waiting for the network"
        case .unavailable: "Not available in this version"
        }
    }

    var symbol: String {
        switch status {
        case .upToDate: "checkmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .paused, .unavailable: "exclamationmark.icloud"
        case .off: "icloud.slash"
        }
    }
}

struct SyncPage: View {
    let session: Session
    @State private var model: SyncViewModel
    @State private var confirmingErase = false

    init(session: Session) {
        self.session = session
        _model = State(initialValue: SyncViewModel(dependencies: session.dependencies))
    }

    var body: some View {
        ThemedForm {
            Section {
                Label(model.statusText, systemImage: model.symbol)
                    .accessibilityIdentifier("sync.status")
                if model.isAvailable {
                    Toggle("Sync with iCloud", isOn: Binding(get: { model.isOn }, set: { on in
                        Task { await model.setOn(on) }
                    }))
                }
                if model.isOn {
                    Button("Sync now") { Task { await model.syncNow() } }
                }
            } footer: {
                Text(model.isAvailable
                     ? "Your business, clients, items, invoices and payments on every iPhone and iPad signed in to your iCloud account. Turning sync off keeps everything on this device."
                     : "This version of the app keeps your data on this device. Use Backup to move it to another device.")
            }
            if case .paused(.accountChanged) = model.status {
                accountChangedSection
            } else if case .paused(.signedOut) = model.status {
                Section {
                    Text("Sign in to iCloud in the Settings app to sync again. Your data stays on this device.")
                }
            } else if case .paused(.quotaExceeded) = model.status {
                Section {
                    Text("Free up iCloud storage, or buy more, to sync again. Your work keeps saving on this device.")
                }
            }
        }
        .disabled(model.isWorking)
        .navigationTitle("iCloud sync")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
        .alert("iCloud sync", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var accountChangedSection: some View {
        Section {
            Text("This device's data came from a different iCloud account. It stays here, unsynced, until you decide.")
            Button("Erase this device's data and sync with this account", role: .destructive) {
                confirmingErase = true
            }
            .confirmationDialog("Erase this device's data?", isPresented: $confirmingErase,
                                titleVisibility: .visible) {
                Button("Erase and sync", role: .destructive) { Task { await model.eraseAndResume() } }
            } message: {
                Text("A copy is kept on this device first. Then the data of the signed-in iCloud account is downloaded.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
