// swift-tools-version: 6.0
// InvoiceData: the GRDB database. Runs the spec's SQL migrations (spec/schema/db/migrations, bundled by
// `make sync-spec`), maps rows to InvoiceCore models and implements InvoiceCore's repository protocols.
import PackageDescription

let package = Package(
    name: "InvoiceData",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "InvoiceData", targets: ["InvoiceData"]),
    ],
    dependencies: [
        .package(path: "../InvoiceCore"),
        .package(url: "https://github.com/groue/GRDB.swift", "7.11.1"..<"8.0.0"),
    ],
    targets: [
        .target(
            name: "InvoiceData",
            dependencies: [
                "InvoiceCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [.copy("Resources/spec")]
        ),
        .testTarget(
            name: "InvoiceDataTests",
            dependencies: ["InvoiceData"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
