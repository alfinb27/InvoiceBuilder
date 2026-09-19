// swift-tools-version: 6.0
// Sync spike, step 1: prove GRDB + SQLiteData resolve and compile with our toolchain and that our v0 schema
// (spec/schema/db/schema.sql) can be registered with SQLiteData's SyncEngine. Steps 2+ need Xcode + 2 devices.
import PackageDescription

let package = Package(
    name: "SyncSpike",
    platforms: [.iOS(.v18), .macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.0.0"),
    ],
    targets: [
        .target(name: "SyncSpike", dependencies: [
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "SQLiteData", package: "sqlite-data"),
        ]),
    ]
)
