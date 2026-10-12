import InvoiceCore
import SwiftUI

/// Settings → Backup's "Google Drive" row: on or off; it opens the Google Drive sheet. (A page pushed one level below
/// a Settings page measures every row as clipped in the accessibility audit; a sheet doesn't.)
struct DriveBackupRow: View {
    let drive: DriveBackupModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            LabeledContent {
                HStack(spacing: Theme.Space.xs) {
                    Text(drive.isConnected ? (drive.hasError ? "Needs attention" : "On") : "Off")
                    Image(systemName: "chevron.right").font(Theme.Fonts.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
            } label: {
                Label("Google Drive", systemImage: "arrow.up.doc")
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .accessibilityIdentifier("backup.drive")
    }
}

/// Settings → Backup → Google Drive (`spec/backup.md` §7.1, §7.5), as a sheet of cards like Review & send.
struct DriveBackupPage: View {
    let drive: DriveBackupModel
    let done: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if drive.isConnected { connected } else { notConnected }
                }
                .padding(Theme.Layout.screenGutter)
                .readableWidth()
            }
            .background(Theme.background)
            .disabled(drive.state.isWorking)
            .navigationTitle("Google Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done).accessibilityIdentifier("backup.drive.done")
                }
            }
        }
    }

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            ScreenHeader(title: "Back up to your Google Drive",
                         subtitle: "Automatically, after you make changes and once a day. Restore on any phone, iPhone or Android.")
            PrimaryButton(title: "Back up to Google Drive automatically", systemImage: "arrow.up.doc",
                          isBusy: drive.state.isWorking) {
                Task { await drive.connect() }
            }
            .accessibilityIdentifier("backup.drive.connect")
            TipCallout("The app only sees the backup files it makes, in a folder called \"InvoiceBuilder backups\". Stop at any time.",
                       systemImage: "lock")
        }
    }

    private var connected: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    row(drive.state.cloud.accountEmail ?? "", systemImage: "person.crop.circle", tint: Theme.textSecondary)
                        .accessibilityLabel("Google account \(drive.state.cloud.accountEmail ?? "")") // what the address is
                        .accessibilityIdentifier("backup.drive.account")
                    Divider().overlay(Theme.surfaceMuted)
                    row(drive.statusText, systemImage: drive.hasError ? "exclamationmark.triangle.fill" : "checkmark.circle",
                        tint: drive.hasError ? Theme.warning : Theme.success)
                        .accessibilityIdentifier("backup.drive.status")
                }
            }
            if drive.state.cloud.lastError == .signedOut {
                PrimaryButton(title: "Connect Google Drive again", systemImage: "arrow.clockwise", isBusy: drive.state.isWorking) {
                    Task { await drive.connect() }
                }
                .accessibilityIdentifier("backup.drive.reconnect")
            } else {
                PrimaryButton(title: "Back up now", systemImage: "arrow.up.circle", isBusy: drive.state.isWorking) {
                    Task { await drive.backUpNow() }
                }
                .accessibilityIdentifier("backup.drive.backUpNow")
            }
            Text("Backs up after you make changes, and once a day, to the \"InvoiceBuilder backups\" folder. Keeps this device's newest 10.")
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Stop backing up to Google Drive") { Task { await drive.disconnect() } }
                .buttonStyle(.textLink)
                .accessibilityHint("Files already in your Drive stay there.")
                .accessibilityIdentifier("backup.drive.disconnect")
        }
    }

    private func row(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Image(systemName: systemImage).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Picks a backup from Google Drive, downloads it and hands it to the usual restore (`spec/backup.md` §7.6, §4).
struct DriveRestoreFlow: ViewModifier {
    @Bindable var drive: DriveBackupModel
    let backup: BackupViewModel
    @State private var chosen: CloudBackupEntry?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $drive.state.showsBackups, onDismiss: restoreChosen) {
                DriveBackupsSheet(backups: drive.state.backups ?? [], now: Date.now,
                                  choose: { entry in
                                      chosen = entry
                                      drive.state.showsBackups = false
                                  },
                                  cancel: { drive.state.showsBackups = false })
            }
            .alert("Google Drive", isPresented: errorBinding) {
                Button("OK", role: .cancel) { drive.dismissError() }
            } message: {
                Text(drive.state.errorMessage ?? "")
            }
    }

    /// After the list is gone, so the restore confirmation can show.
    private func restoreChosen() {
        guard let entry = chosen else { return }
        chosen = nil
        Task {
            if let bytes = await drive.download(entry) { backup.load(bytes) }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { drive.state.errorMessage != nil }, set: { if !$0 { drive.dismissError() } })
    }
}

extension View {
    /// The Google Drive restore list, when this build has Drive backup.
    @ViewBuilder
    func driveRestoreFlow(drive: DriveBackupModel?, backup: BackupViewModel) -> some View {
        if let drive {
            modifier(DriveRestoreFlow(drive: drive, backup: backup))
        } else {
            self
        }
    }
}

/// §7.6: the backups in the user's Drive, newest first, with the device and what each holds.
struct DriveBackupsSheet: View {
    let backups: [CloudBackupEntry]
    let now: Date
    let choose: (CloudBackupEntry) -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if backups.isEmpty {
                    ContentUnavailableView(
                        "No backups in Google Drive yet", systemImage: "arrow.down.doc",
                        description: Text("Backups appear here once the app on your other phone has backed up to this Google account."))
                } else {
                    List {
                        Section {
                            ForEach(Array(backups.enumerated()), id: \.element.id) { index, entry in
                                Button {
                                    choose(entry)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(DriveBackupText.title(entry, now: nowMillis))
                                            .font(Theme.Fonts.rowTitle)
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(DriveBackupText.detail(entry))
                                            .font(Theme.Fonts.footnote)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .accessibilityIdentifier("driveBackup-\(index)")
                            }
                        } footer: {
                            Text("Restoring replaces all the data on this device. A copy of the current data is kept first.")
                        }
                    }
                    .themedList()
                }
            }
            .navigationTitle("Restore from Google Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
            }
        }
    }

    private var nowMillis: Int64 { Int64((now.timeIntervalSince1970 * 1000).rounded()) }
}
