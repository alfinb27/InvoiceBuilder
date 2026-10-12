import InvoiceCore
import SwiftUI

/// The first issue on a device that owns no series of this type (`spec/sync.md` §3): start numbering here, or
/// continue a series another device used.
struct SeriesChoiceSheet: View {
    let choice: DocumentViewModel.SeriesChoice
    let docType: DocumentType
    let startOwn: () -> Void
    let takeOver: (String) -> Void
    let cancel: () -> Void
    @State private var pendingTakeOver: DocumentViewModel.SeriesChoice.Option?

    var body: some View {
        NavigationStack {
            ThemedForm {
                if let first = choice.ownFirstNumber {
                    Section {
                        Button(action: startOwn) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text("Start numbering on this device")
                                Text("The first will be \(first)")
                                    .font(Theme.Fonts.subhead).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .accessibilityIdentifier("series.startOwn")
                    } footer: {
                        Text("Each device numbers from its own series, so two devices never give out the same number.")
                    }
                }
                if !choice.others.isEmpty {
                    Section {
                        ForEach(choice.others) { option in
                            Button {
                                pendingTakeOver = option
                            } label: {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    Text(option.series.label)
                                    if let next = option.nextNumber {
                                        Text("Continues with \(next)")
                                            .font(Theme.Fonts.subhead).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Continue another device's series")
                    } footer: {
                        Text("Only if that device no longer issues \(DocumentText.noun(docType))s, such as a phone you replaced.")
                    }
                }
            }
            .navigationTitle("Numbering on this device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
            }
            .confirmationDialog("Continue \(pendingTakeOver?.series.label ?? "")?", isPresented: takeOverBinding,
                                titleVisibility: .visible, presenting: pendingTakeOver) { option in
                Button("Continue on this device") { takeOver(option.series.id) }
            } message: { _ in
                Text("The other device will have to choose numbering again before it issues.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var takeOverBinding: Binding<Bool> {
        Binding(get: { pendingTakeOver != nil }, set: { if !$0 { pendingTakeOver = nil } })
    }
}
