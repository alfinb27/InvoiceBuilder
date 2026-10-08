// swift-tools-version: 6.0
// InvoiceSync: iCloud sync with SQLiteData's SyncEngine (ADR-0015, spec/sync.md), behind InvoiceCore's
// `SyncService`. The only package that imports SQLiteData.
import PackageDescription

let package = Package(
    name: "InvoiceSync",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "InvoiceSync", targets: ["InvoiceSync"]),
    ],
    dependencies: [
        .package(path: "../InvoiceCore"),
        .package(path: "../InvoiceData"),
        .package(url: "https://github.com/groue/GRDB.swift", "7.11.1"..<"8.0.0"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", "1.12.0"..<"2.0.0"),
    ],
    targets: [
        .target(
            name: "InvoiceSync",
            dependencies: [
                "InvoiceCore",
                "InvoiceData",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SQLiteData", package: "sqlite-data"),
            ]
        ),
        .testTarget(
            name: "InvoiceSyncTests",
            dependencies: ["InvoiceSync"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
