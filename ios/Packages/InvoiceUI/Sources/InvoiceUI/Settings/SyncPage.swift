import InvoiceCore
import Observation
import SwiftUI

/// Settings → Sync: iCloud (`spec/sync.md` §2) or Google Drive (`spec/drive-sync.md` §1), one at a time.
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

    func setOn(_ on: Bool, driveSync: DriveSyncModel? = nil) async {
        isWorking = true
        defer { isWorking = false }
        // One sync method per device (`spec/drive-sync.md` §1).
        if on, let driveSync, driveSync.isOn { await driveSync.disconnect() }
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
    @State private var drive: DriveSyncModel?
    @State private var confirmingErase = false
    @State private var confirmingDrive = false

    init(session: Session) {
        self.session = session
        _model = State(initialValue: SyncViewModel(dependencies: session.dependencies))
        _drive = State(initialValue: session.driveSync.map { engine in
            DriveSyncModel(engine: engine, store: session.dependencies.driveSyncStore, iCloud: session.dependencies.sync,
                           autoBackup: session.autoBackup, time: session.dependencies.time,
                           onMerged: { [weak session] _ in await session?.reconcileReminders() })
        })
    }

    /// Cards in a scroll view rather than a Form: the accessibility audit measures conditional Form rows on a
    /// Settings page as clipped.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                iCloudCard
                if let drive { driveCard(drive) }
            }
            .padding(Theme.Layout.screenGutter)
            .readableWidth()
        }
        .background(Theme.background)
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
        .task { await drive?.observe() }
        .alert("iCloud sync", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: iCloud (`spec/sync.md` §2)

    private var iCloudCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("iCloud").font(Theme.Fonts.headline).foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            SurfaceCard {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    statusRow(model.statusText, systemImage: model.symbol, tint: Theme.textSecondary)
                        .accessibilityIdentifier("sync.status")
                    if model.isAvailable {
                        Divider().overlay(Theme.surfaceMuted)
                        Toggle("Sync with iCloud", isOn: Binding(get: { model.isOn }, set: { on in
                            Task { await model.setOn(on, driveSync: drive) }
                        }))
                        .font(Theme.Fonts.body)
                        .accessibilityIdentifier("sync.icloud")
                    }
                    if model.isOn {
                        Button("Sync now") { Task { await model.syncNow() } }
                            .buttonStyle(.textLink)
                    }
                }
            }
            .disabled(model.isWorking)
            footnote(model.isAvailable
                     ? "Your business, clients, items, invoices and payments on every iPhone and iPad signed in to your iCloud account. Turning sync off keeps everything on this device."
                     : drive == nil
                        ? "This version of the app keeps your data on this device. Use Backup to move it to another device."
                        : "iCloud sync isn't available in this version.")
            if case .paused(.accountChanged) = model.status {
                accountChanged
            } else if case .paused(.signedOut) = model.status {
                footnote("Sign in to iCloud in the Settings app to sync again. Your data stays on this device.")
            } else if case .paused(.quotaExceeded) = model.status {
                footnote("Free up iCloud storage, or buy more, to sync again. Your work keeps saving on this device.")
            }
        }
    }

    private var accountChanged: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            footnote("This device's data came from a different iCloud account. It stays here, unsynced, until you decide.")
            Button("Erase this device's data and sync with this account", role: .destructive) {
                confirmingErase = true
            }
            .buttonStyle(.textLink)
            .confirmationDialog("Erase this device's data?", isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Erase and sync", role: .destructive) { Task { await model.eraseAndResume() } }
            } message: {
                Text("A copy is kept on this device first. Then the data of the signed-in iCloud account is downloaded.")
            }
        }
    }

    // MARK: Google Drive (`spec/drive-sync.md` §1, §7, §9)

    private func driveCard(_ drive: DriveSyncModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Google Drive").font(Theme.Fonts.headline).foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            SurfaceCard {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    statusRow(drive.statusText,
                              systemImage: drive.hasError ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath",
                              tint: drive.hasError ? Theme.warning : Theme.textSecondary)
                        .accessibilityIdentifier("sync.drive.status")
                    Divider().overlay(Theme.surfaceMuted)
                    Toggle("Sync with Google Drive", isOn: Binding(get: { drive.isOn }, set: { on in
                        if on { confirmingDrive = true } else { Task { await drive.disconnect() } }
                    }))
                    .font(Theme.Fonts.body)
                    .accessibilityIdentifier("sync.drive")
                    if drive.isOn {
                        Button("Sync now") { Task { await drive.syncNow() } }
                            .buttonStyle(.textLink)
                            .accessibilityIdentifier("sync.drive.now")
                    }
                }
            }
            .disabled(drive.state.isWorking)
            footnote("Works between iPhones, iPads and Android phones through your own Google Drive. Choosing it turns "
                     + "iCloud sync off on this device. Turning it off keeps everything here and in Drive.")
        }
        .confirmationDialog("Sync with Google Drive?", isPresented: $confirmingDrive, titleVisibility: .visible) {
            Button("Sync with Google Drive") { Task { await drive.connect() } }
                .accessibilityIdentifier("sync.drive.confirm")
        } message: {
            Text("The businesses on this device and in your Google Drive will be combined. iCloud sync turns off on "
                 + "this device.")
        }
        .alert("Google Drive", isPresented: Binding(get: { drive.state.errorMessage != nil },
                                                    set: { if !$0 { drive.dismissError() } })) {
            Button("OK", role: .cancel) { drive.dismissError() }
        } message: {
            Text(drive.state.errorMessage ?? "")
        }
    }

    private func statusRow(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Image(systemName: systemImage).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
