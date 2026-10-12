// swift-tools-version: 6.0
// InvoiceBilling: StoreKit 2 and the free-tier count (spec/billing.md, ADR-0008), behind InvoiceCore's
// `EntitlementService`. StoreKit sits behind `StoreClient`, so every state transition is tested with a fake store.
import PackageDescription

let package = Package(
    name: "InvoiceBilling",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "InvoiceBilling", targets: ["InvoiceBilling"]),
    ],
    dependencies: [
        .package(path: "../InvoiceCore"),
    ],
    targets: [
        .target(name: "InvoiceBilling", dependencies: ["InvoiceCore"]),
        .testTarget(name: "InvoiceBillingTests", dependencies: ["InvoiceBilling"]),
    ],
    swiftLanguageModes: [.v6]
)
