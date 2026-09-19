import InvoiceCore
import SwiftUI

/// The root of the app: onboarding until a business exists, then the adaptive shell.
public struct AppRootView: View {
    @State private var model: AppModel

    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
            case .onboarding(let onboarding):
                OnboardingView(model: onboarding)
            case .ready(let session):
                MainShellView(session: session)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Your data couldn't be opened", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            }
        }
        .tint(Theme.brand)
        .task { await model.start() }
    }
}

/// Tabs on iPhone, a sidebar on iPad (`.sidebarAdaptable`, ADR-0010/0014). Each section is a list/detail split view
/// whose navigation state lives in `session.router`.
public struct MainShellView: View {
    let session: Session

    public init(session: Session) {
        self.session = session
    }

    public var body: some View {
        @Bindable var router = session.router
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeView(session: session)
            }
            Tab("Clients", systemImage: "person.2", value: AppTab.clients) {
                ClientsSection(session: session)
            }
            Tab("Items", systemImage: "shippingbox", value: AppTab.items) {
                CatalogSection(session: session)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsSection(session: session)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(session)
        .task { await session.observeBusiness() }
    }
}
