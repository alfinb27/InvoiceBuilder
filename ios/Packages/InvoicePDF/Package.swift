// swift-tools-version: 6.0
// InvoicePDF: draws a document natively from the shared view model and template (ADR-0006). Core Text inside
// UIGraphicsPDFRenderer; the Android renderer draws the same spec with PdfDocument + StaticLayout.
import PackageDescription

let package = Package(
    name: "InvoicePDF",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "InvoicePDF", targets: ["InvoicePDF"]),
    ],
    dependencies: [
        .package(path: "../InvoiceCore"),
    ],
    targets: [
        .target(name: "InvoicePDF", dependencies: ["InvoiceCore"]),
        .testTarget(name: "InvoicePDFTests", dependencies: ["InvoicePDF"]),
    ],
    swiftLanguageModes: [.v6]
)
