import InvoiceUI
import SwiftUI

/// The app target stays thin: everything lives in the local packages (ADR-0009).
@main
struct InvoiceApp: App {
    @State private var model = AppModel.launch()

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model)
        }
    }
}
