import InvoiceCore
import PDFKit
import SwiftUI

/// Review & send (`spec/documents.md` §6.1, `docs/design/design.md` §6.6): what is being sent, the number it will
/// get and that it locks, the channel, and what happens next. Its button closes the review; the document is issued
/// and the channel opens once the sheet is gone (`DocumentViewModel.sendAfterReview`).
struct ReviewSendView: View {
    @Bindable var model: DocumentViewModel
    let session: Session
    @State private var channel: SendChannel = .whatsApp
    @State private var thumbnail: UIImage?
    @State private var fullPreview: DocumentPreviewViewModel?
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The channel icon's circle grows with the label under it.
    @ScaledMetric(relativeTo: .body) private var channelIcon: CGFloat = 36

    private var document: InvoiceCore.Document { model.state.document }
    private var noun: String { DocumentText.noun(document.docType) }
    private var taxName: String { model.config.labels.taxName }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Looks good. Ready to send?")
                        .font(Theme.Fonts.title3)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Theme.Space.xs)
                    summary
                    lockTip
                    Text("Send it by")
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, Theme.Space.s)
                        .accessibilityAddTraits(.isHeader)
                    channels
                    Text("What happens next")
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, Theme.Space.s)
                        .accessibilityAddTraits(.isHeader)
                    timeline
                }
                .padding(.horizontal, Theme.Layout.screenGutter)
                .padding(.vertical, Theme.Space.s)
                .readableWidth()
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", systemImage: "chevron.backward") { model.keepAsDraft() }
                        .accessibilityLabel("Back to editing")
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .sheet(item: $fullPreview) { DocumentPreviewView(model: $0) }
            .task { await renderThumbnail() }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: What is being sent

    private var summary: some View {
        HStack(alignment: .center, spacing: Theme.Space.m + 2) {
            page
            VStack(alignment: .leading, spacing: 3) {
                // One element for VoiceOver: who, how much, how many and when.
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipientLine).font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
                    Text(model.computed.map { session.money($0.totals.total, currency: document.currency) } ?? "—")
                        .font(Theme.Fonts.amountLarge)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(itemsLine).font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
                    if let dateLine {
                        Text(dateLine).font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Button("See full \(noun)") { openFullPreview() }
                    .buttonStyle(.textLink)
                    .accessibilityIdentifier("review.seeFull")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.m + 2)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.border))
        .accessibilityElement(children: .contain)
    }

    /// The first page of the PDF, small; a sketch of one while it renders.
    private var page: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFit()
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.brand).frame(width: 14, height: 14)
                    ForEach([0.7, 0.5, 0.85, 0.85], id: \.self) { fraction in
                        RoundedRectangle(cornerRadius: 2).fill(Theme.border).frame(width: 74 * fraction, height: 4)
                    }
                    Spacer()
                }
                .padding(9)
            }
        }
        .frame(width: 92, height: 122)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .shadow(color: Theme.shadow.opacity(0.08), radius: 6, y: 4)
        .accessibilityHidden(true)
    }

    private var recipientLine: String {
        let name = model.state.client?.name ?? document.buyerSnapshot?.name
        return name.map { "\(noun.capitalized) to \($0)" } ?? "\(noun.capitalized) for a walk-in customer"
    }

    private var itemsLine: String {
        let count = document.lines.count
        var text = "\(count) item\(count == 1 ? "" : "s")"
        if let computed = model.computed, computed.chargesTax, computed.totals.tax != 0 {
            text += " · \(taxName) included"
        }
        return text
    }

    private var dateLine: String? {
        if document.docType == .quote { return document.validUntil.map { "Valid until \($0.displayText)" } }
        return document.dueDate.map { "Due \($0.displayText)" }
    }

    private var lockTip: some View {
        let reason = document.docType == .invoice && model.chargesTax
            ? "so your \(taxName) records stay correct." : "so it can't change once your client has it."
        let number = model.state.numberPreview.map { Text(" ") + Text($0).bold() } ?? Text("")
        return TipCallout(text: Text("Sending gives it the number") + number + Text(" and locks it, \(reason) ")
                              + Text("Not ready? It stays a draft you can edit."),
                          systemImage: "lock")
            .accessibilityIdentifier("review.lockTip")
    }

    // MARK: Channel

    private var channels: some View {
        // Four tiles in a row; one row each, icon then label, at accessibility text sizes.
        let stacked = typeSize.isAccessibilitySize
        let rowLayout = stacked ? AnyLayout(VStackLayout(spacing: Theme.Space.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.s))
        let tileLayout = stacked ? AnyLayout(HStackLayout(spacing: Theme.Space.m))
            : AnyLayout(VStackLayout(spacing: 6))
        return rowLayout {
            ForEach(SendChannel.allCases) { option in
                Button {
                    channel = option
                } label: {
                    tileLayout {
                        Image(systemName: option.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(channel == option ? Theme.brandOn : Theme.textPrimary)
                            .frame(width: channelIcon, height: channelIcon)
                            .background(channel == option ? Theme.brand : Theme.surfaceMuted, in: Circle())
                        Text(option.label)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(stacked ? .leading : .center)
                            .fixedSize(horizontal: false, vertical: true)
                        if stacked { Spacer(minLength: 0) }
                    }
                    .frame(maxWidth: .infinity, minHeight: stacked ? nil : 76)
                    .padding(.vertical, Theme.Space.xs)
                    .padding(.horizontal, stacked ? Theme.Space.m : 0)
                    .background(channel == option ? Theme.brandTint : Theme.surface,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .strokeBorder(channel == option ? Theme.brand : Theme.border, lineWidth: channel == option ? 2 : 1))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(channel == option ? .isSelected : [])
                .accessibilityIdentifier("channel-\(option.rawValue)")
            }
        }
    }

    // MARK: What happens next

    private var timeline: some View {
        let steps = nextSteps
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    VStack(spacing: 0) {
                        Circle()
                            .strokeBorder(index == 0 ? Theme.brand : Theme.control, lineWidth: 2)
                            .background(Circle().fill(index == 0 ? Theme.brand : Color.clear))
                            .frame(width: 12, height: 12)
                            .padding(.top, 4)
                        if index < steps.count - 1 {
                            Rectangle().fill(Theme.borderStrong).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 12)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(Theme.Fonts.subhead.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        if let hint = step.hint {
                            Text(hint).font(Theme.Fonts.caption.weight(.regular)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, index < steps.count - 1 ? Theme.Space.m : 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var nextSteps: [(title: String, hint: String?)] {
        if document.docType == .quote {
            return [("Shown as “Sent” in your quotes", nil),
                    ("Mark it accepted or declined when your client answers", nil),
                    ("Turn it into an invoice in one tap", nil)]
        }
        let days = document.reminderDaysAfterDueOverride ?? session.business.reminderDaysAfterDue
        let reminder: (String, String?)
        if let due = document.dueDate, let days {
            reminder = ("We nudge you if it's unpaid by \(due.adding(days: days).displayText)",
                        "A reminder on your phone. Nothing is sent to your client.")
        } else if let due = document.dueDate {
            reminder = ("It shows as past due if it's unpaid after \(due.displayText)",
                        "Turn on payment reminders in Settings to get a nudge on your phone.")
        } else {
            reminder = ("It shows as waiting to be paid until it is", nil)
        }
        return [("Shown as “Sent” on your home screen", nil), reminder,
                ("Tap “Record payment” when the money arrives", nil)]
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Theme.Space.xs) {
            PrimaryButton(title: channel.buttonTitle(for: document.docType)) { model.send(via: channel) }
                .accessibilityIdentifier("review.send")
            Button("Keep as draft") { model.keepAsDraft() }
                .buttonStyle(.textLink)
                .accessibilityIdentifier("review.keepDraft")
        }
        .padding(.horizontal, Theme.Layout.screenGutter)
        .padding(.top, Theme.Space.m)
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: Theme.Layout.maxReadableWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottomBar")
    }

    private func openFullPreview() {
        guard let computed = model.computed else { return }
        fullPreview = DocumentPreviewViewModel(session: session, document: model.documentToRender, computed: computed)
    }

    private func renderThumbnail() async {
        guard let computed = model.computed,
              let data = try? await session.pdfLibrary.data(for: model.documentToRender, business: session.business,
                                                            computed: computed),
              let page = PDFDocument(data: data)?.page(at: 0) else { return }
        thumbnail = page.thumbnail(of: CGSize(width: 276, height: 366), for: .mediaBox)
    }
}
