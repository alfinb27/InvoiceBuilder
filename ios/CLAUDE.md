# iOS / iPadOS app rules

Read the root `CLAUDE.md` first. This file adds iOS-specific conventions. (The app is created in Phase 1.)

## Stack

- Swift 6 language mode, strict concurrency. Minimum iOS/iPadOS 18. Universal app (iPhone + iPad).
- SwiftUI; `@Observable @MainActor` view models holding one `State` value each; one-way data flow.
- GRDB (`DatabasePool`, WAL) for persistence; SQLiteData sync layer (inside `InvoiceSync` only) for iCloud.
- StoreKit 2 (`InvoiceBilling`). PDFKit / `UIGraphicsPDFRenderer` / WebKit per the PDF ADR.
- Dependencies are limited to GRDB, SQLiteData and `swift-snapshot-testing` (tests). Anything else needs an ADR.

## Packages (`ios/Packages/`)

| Package | Rule |
|---|---|
| `InvoiceCore` | Pure Swift + Foundation. No UIKit/SwiftUI/GRDB imports. All tax, money, numbering, validation, status, backup codec. |
| `InvoiceData` | GRDB migrations (mirroring `spec/schema/db/migrations`), records, repository implementations. |
| `InvoicePDF` | Renderer and bundled templates. Renders only `ComputedDocument` output. |
| `InvoiceBilling` | StoreKit 2 + `EntitlementService` implementing `spec/billing.md`. |
| `InvoiceSync` | SQLiteData sync engine behind a `SyncService` protocol. `DeviceState` is never synced. |
| `InvoiceUI` | Design system + feature screens. |

## Conventions

- Core types are `Sendable` value types. Pass IDs, not records, across actors.
- Every screen must work from compact to regular width; navigation state lives in routers, never in views,
  so it survives iPad window resizing and size-class changes.
- Drafts autosave (500 ms debounce). Never keep unsaved invoice data only in memory.
- Money: `Money(minorUnits: Int64, currency: CurrencyCode)`. Decimal parsing uses the spec parser, never
  `Decimal(string:)` directly (it accepts partial input such as `"1.5abc"`).
- `UUID().uuidString` is uppercase; always store `.uuidString.lowercased()`.

## Commands (once the packages exist)

```sh
swift test --package-path ios/Packages/InvoiceCore      # all spec fixtures, no simulator
xcodebuild test -scheme InvoiceApp -destination 'platform=iOS Simulator,name=<current iPhone>'
xcodebuild test -scheme InvoiceApp -destination 'platform=iOS Simulator,name=<current iPad Pro 13-inch>'
```

Full Xcode is required for app targets, simulators and StoreKit testing; Command Line Tools are enough for
`swift test` on `InvoiceCore`.
