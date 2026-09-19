// swift-tools-version: 6.0
// InvoiceCore: pure Swift + Foundation (no UIKit, SwiftUI or GRDB). Money, dates, tax configs, validators,
// numbering, formatting, domain models, setup rules and repository protocols. `swift test` runs the spec fixtures.
import PackageDescription

let package = Package(
    name: "InvoiceCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "InvoiceCore", targets: ["InvoiceCore"]),
    ],
    targets: [
        .target(
            name: "InvoiceCore",
            // Runtime copy of spec/ (tax, reference, pdf/labels, pdf/fonts, design), written by `make sync-spec`.
            resources: [.copy("Resources/spec")]
        ),
        .testTarget(
            name: "InvoiceCoreTests",
            dependencies: ["InvoiceCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
