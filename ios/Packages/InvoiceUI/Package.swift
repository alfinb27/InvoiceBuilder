// swift-tools-version: 6.0
// InvoiceUI: the design system and feature screens (onboarding, clients, catalogue, settings) plus the adaptive
// app shell and `AppDependencies`. iOS only: build and test it with xcodebuild on a simulator.
import PackageDescription

let package = Package(
    name: "InvoiceUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "InvoiceUI", targets: ["InvoiceUI"]),
    ],
    dependencies: [
        .package(path: "../InvoiceCore"),
        .package(path: "../InvoiceData"),
    ],
    targets: [
        .target(
            name: "InvoiceUI",
            dependencies: ["InvoiceCore", "InvoiceData"]
        ),
        .testTarget(
            name: "InvoiceUITests",
            dependencies: ["InvoiceUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
