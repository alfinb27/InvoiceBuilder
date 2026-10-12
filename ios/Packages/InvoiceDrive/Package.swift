// swift-tools-version: 6.0
// InvoiceDrive: automatic backup to the user's Google Drive (spec/backup.md §7, ADR-0021), behind InvoiceCore's
// `CloudBackupDestination`. No Google SDK: OAuth 2.0 for native apps with PKCE (ASWebAuthenticationSession) and
// Drive REST v3 over URLSession, both behind `HTTPClient` so every request is tested without a network.
import PackageDescription

let package = Package(
    name: "InvoiceDrive",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "InvoiceDrive", targets: ["InvoiceDrive"]),
    ],
    dependencies: [
        .package(path: "../InvoiceCore"),
    ],
    targets: [
        .target(name: "InvoiceDrive", dependencies: ["InvoiceCore"]),
        .testTarget(name: "InvoiceDriveTests", dependencies: ["InvoiceDrive"]),
    ],
    swiftLanguageModes: [.v6]
)
