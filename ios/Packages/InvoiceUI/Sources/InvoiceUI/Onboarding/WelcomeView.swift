import SwiftUI

/// The first screen (`docs/design/design.md` §6.1): what the app does in three promises, then "Let's get started".
/// "I've used this app before" restores; "Just looking?" opens the sample business.
struct WelcomeView: View {
    @Bindable var model: OnboardingViewModel
    @State private var showsRestore = false
    @State private var showsSamples = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Space.s + 2) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.brandOn)
                        .frame(width: 32, height: 32)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 10))
                    Text("InvoiceBuilder")
                        .font(Theme.Fonts.title3)
                        .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityElement(children: .combine)
                WelcomeIllustration()
                    .padding(.top, Theme.Space.l + 4)
                ScreenHeader(title: "Send a proper invoice in about a minute.",
                             subtitle: "No accounting jargon. We'll guide you one simple question at a time.",
                             large: true)
                    .padding(.top, Theme.Space.xl)
                VStack(alignment: .leading, spacing: Theme.Space.m + 2) {
                    Promise(number: 1, title: "Tell us about your business", hint: "Once, about 2 minutes")
                    Promise(number: 2, title: "Add who you're billing and what you sold",
                            hint: "We work out the GST or VAT for you")
                    Promise(number: 3, title: "Send it on WhatsApp or email", hint: "Then see at a glance who has paid")
                }
                .padding(.top, Theme.Space.l + 6)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.l + 4)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { actions }
        .confirmationDialog("Welcome back", isPresented: $showsRestore, titleVisibility: .visible) {
            Button("Restore from a backup file") { model.backup.state.showsImporter = true }
                .accessibilityIdentifier("onboarding.restore")
        } message: {
            Text("Used iCloud on another iPhone or iPad? Your business appears here by itself once this device is "
                 + "signed in to the same Apple Account. Otherwise, start from an InvoiceBuilder backup file.")
        }
        .confirmationDialog("Try a sample business", isPresented: $showsSamples, titleVisibility: .visible) {
            Button("A sample Indian business") { Task { await model.tryDemo(.india) } }
                .accessibilityIdentifier("onboarding.demoIN")
            Button("A sample UK business") { Task { await model.tryDemo(.uk) } }
                .accessibilityIdentifier("onboarding.demoGB")
        } message: {
            Text("See invoices, quotes and payments in a sample business. Nothing you do there is saved.")
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.xs) {
            Label("Your data stays on your phone. No account needed.", systemImage: "lock")
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, Theme.Space.s + 2)
            PrimaryButton(title: "Let's get started", trailingArrow: true) { model.start() }
                .accessibilityIdentifier("onboarding.start")
            HStack(spacing: Theme.Space.l) {
                Button("I've used this app before") { showsRestore = true }
                    .accessibilityIdentifier("onboarding.usedBefore")
                Button("Just looking?") { showsSamples = true }
                    .accessibilityIdentifier("onboarding.justLooking")
            }
            .buttonStyle(.textLink)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottomBar")
    }
}

/// One numbered promise on the Welcome screen.
private struct Promise: View {
    let number: Int
    let title: String
    let hint: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m + 2) {
            Text("\(number)")
                .font(Theme.Fonts.subhead.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.borderStrong, lineWidth: 1.5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.rowTitle).foregroundStyle(Theme.textPrimary)
                Text(hint).font(Theme.Fonts.footnote).foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The hero: an invoice card, a "PAID" stamp and a paper plane on the brand tint. Decoration only.
private struct WelcomeIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.hero).fill(Theme.brandTint)
            invoiceCard
                .rotationEffect(.degrees(-4))
                .offset(x: -40, y: 20)
            Text("PAID")
                .font(Theme.Fonts.display(18))
                .tracking(1)
                .foregroundStyle(Color(red: 42 / 255, green: 33 / 255, blue: 53 / 255))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.highlight, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(red: 42 / 255, green: 33 / 255, blue: 53 / 255), lineWidth: 2.5))
                .rotationEffect(.degrees(10))
                .offset(x: 80, y: 30)
            Image(systemName: "paperplane")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: 46, height: 46)
                .background(Theme.surface, in: Circle())
                .shadow(color: Theme.shadow.opacity(0.1), radius: 6, y: 4)
                .offset(x: 110, y: -52)
        }
        .frame(height: 196)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero))
        .accessibilityHidden(true)
    }

    private var invoiceCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                RoundedRectangle(cornerRadius: 7).fill(Theme.brand).frame(width: 22, height: 22)
                Spacer()
                Text("INVOICE").font(Theme.Fonts.display(10)).tracking(1).foregroundStyle(Theme.textSecondary)
            }
            bar(0.7)
            bar(0.5)
            Rectangle().fill(Theme.surfaceMuted).frame(height: 1).padding(.vertical, 4)
            HStack { bar(0.55); Spacer(); bar(0.2) }
            HStack { bar(0.45); Spacer(); bar(0.2) }
            HStack(alignment: .firstTextBaseline) {
                Text("Total").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("₹20,060").font(Theme.Fonts.display(18)).foregroundStyle(Theme.textPrimary)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 176, height: 196, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Theme.shadow.opacity(0.12), radius: 12, y: 8)
    }

    private func bar(_ fraction: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(Theme.border).frame(width: 144 * fraction, height: 6)
    }
}
