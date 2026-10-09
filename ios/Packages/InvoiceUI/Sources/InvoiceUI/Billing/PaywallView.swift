import InvoiceCore
import SwiftUI

/// The unlock (`spec/billing.md`): the store's localised price, Restore purchases, and Ask to Buy's waiting state.
/// Shown when Issue is tapped at the limit, and from Settings. Nothing else in the app is ever locked.
struct PaywallView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

    private var status: EntitlementStatus { session.entitlement }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Image(systemName: status.isUnlocked ? "checkmark.seal.fill" : "infinity.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.brand)
                        .frame(maxWidth: .infinity)
                    Text(headline)
                        .font(Theme.Fonts.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Text(detail)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        benefit("Send as many invoices as you need", symbol: "doc.badge.plus")
                        benefit("One payment, no subscription", symbol: "creditcard")
                        benefit("On every device with your Apple ID, family included", symbol: "person.2")
                        benefit("Your invoices, quotes and backups were never locked", symbol: "lock.open")
                    }
                    .padding(.vertical, Theme.Space.s)
                    actions
                    Text("A one-time purchase. Payment is charged to your Apple ID account at confirmation.")
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(Theme.Space.l)
                .readableWidth()
            }
            .navigationTitle("Unlimited invoices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .disabled(isWorking)
        }
        .onChange(of: status.state) { _, state in
            if state == .unlocked { Task { try? await Task.sleep(for: .seconds(1)); dismiss() } }
        }
    }

    @ViewBuilder private var actions: some View {
        switch status.state {
        case .unlocked:
            EmptyView()
        case .pending:
            Label("Waiting for approval. You can keep working; invoices unlock when the purchase is approved.",
                  systemImage: "hourglass")
                .foregroundStyle(Theme.textSecondary)
        default:
            PrimaryButton(title: buyTitle, isBusy: isWorking || status.state == .purchasing) {
                Task {
                    isWorking = true
                    await session.dependencies.entitlements.purchase()
                    isWorking = false
                }
            }
            .disabled(status.displayPrice == nil)
            .accessibilityIdentifier("paywall.buy")
            if status.displayPrice == nil {
                Text("The App Store can't be reached right now.")
                    .font(Theme.Fonts.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        Button("Restore purchases") {
            Task {
                isWorking = true
                await session.dependencies.entitlements.restore()
                isWorking = false
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("paywall.restore")
    }

    private var buyTitle: String {
        status.displayPrice.map { "Unlock for \($0)" } ?? "Unlock"
    }

    private var headline: String {
        switch status.state {
        case .unlocked: "Unlimited invoices are on"
        case .limitReached: "You've used your \(FreeTier.limit) free invoices"
        default: "\(status.remaining) of \(FreeTier.limit) free invoices left"
        }
    }

    private var detail: String {
        status.isUnlocked
            ? "Thank you. Send as many invoices as you need."
            : "Unlock unlimited invoices once, on every device you use."
    }

    private func benefit(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
    }
}

/// Settings → Unlimited invoices.
struct UnlockPage: View {
    let session: Session
    @State private var showsPaywall = false

    var body: some View {
        ThemedForm {
            Section {
                LabeledContent("Status", value: statusText)
                    .accessibilityIdentifier("unlock.status")
                if !session.entitlement.isUnlocked {
                    LabeledContent("Free invoices left", value: "\(session.entitlement.remaining) of \(FreeTier.limit)")
                    Button("Unlock unlimited invoices") { showsPaywall = true }
                }
                Button("Restore purchases") { Task { await session.dependencies.entitlements.restore() } }
            } footer: {
                Text("Quotes, drafts, sharing and backups are always free. Only issuing invoices beyond \(FreeTier.limit) needs the unlock.")
            }
        }
        .navigationTitle("Unlimited invoices")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPaywall) { PaywallView(session: session) }
    }

    private var statusText: String {
        switch session.entitlement.state {
        case .unlocked: "Unlocked"
        case .pending: "Waiting for approval"
        case .purchasing: "Purchasing…"
        case .unknown: "Checking…"
        case .free, .limitReached: "Free"
        }
    }
}
