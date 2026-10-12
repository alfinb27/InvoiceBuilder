import Foundation
import GRDB
import InvoiceCore
import InvoiceData
import SQLiteData
import Testing
@testable import InvoiceSync

@Suite("Sync")
struct InvoiceSyncTests {
    /// Every column of every synced table is a column of its `@Table` mirror, and nothing else (`spec/sync.md` §1).
    @Test func tableMirrorsMatchTheSchema() async throws {
        let database = try AppDatabase.inMemory()
        let mirrors: [(String, [String])] = [
            ("business", SyncedBusiness.TableColumns.writableColumns.map(\.name)),
            ("asset", SyncedAsset.TableColumns.writableColumns.map(\.name)),
            ("client", SyncedClient.TableColumns.writableColumns.map(\.name)),
            ("catalog_item", SyncedCatalogItem.TableColumns.writableColumns.map(\.name)),
            ("numbering_series", SyncedNumberingSeries.TableColumns.writableColumns.map(\.name)),
            ("document", SyncedDocument.TableColumns.writableColumns.map(\.name)),
            ("line_item", SyncedLineItem.TableColumns.writableColumns.map(\.name)),
            ("tax_line", SyncedTaxLine.TableColumns.writableColumns.map(\.name)),
            ("payment", SyncedPayment.TableColumns.writableColumns.map(\.name)),
        ]
        #expect(mirrors.map(\.0) == SyncedTables.names)
        for (table, columns) in mirrors {
            let schema = try await database.writer.read { db in try db.columns(in: table).map(\.name) }
            #expect(Set(columns) == Set(schema), "\(table): mirror \(columns.sorted()) vs schema \(schema.sorted())")
        }
        // Every synced table of the schema is mirrored; only the local tables are left out.
        let all = try await database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                  AND name NOT LIKE 'grdb_%'
                """)
        }
        #expect(Set(all).subtracting(SyncedTables.names) == ["device_state", "app_state"])
    }

    /// SQLiteData validates the schema when the engine starts (primary keys, no UNIQUE, ON DELETE actions); in
    /// tests it runs against an in-memory CloudKit mock.
    @Test func theSyncEngineAcceptsTheSchema() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "InvoiceSyncTests-\(UUID().uuidString)")
        let container = "iCloud.app.invoicebuilder.tests"
        let database = try AppDatabase.openOnDisk(at: folder.appending(path: "invoices.sqlite")) {
            LiveSyncService.prepare(&$0, containerIdentifier: container)
        }
        let time = TimeSource.fixed(now: 1_789_800_000_000, today: LocalDate(iso: "2026-09-19")!)
        let devices = GRDBDeviceStateRepository(database: database, time: time, ids: .sequential(),
                                                marker: InMemoryDeviceMarkerStore())
        _ = try await devices.loadOrCreate(deviceName: "Test")
        let service = try LiveSyncService(database: database, containerIdentifier: container, deviceState: devices,
                                          enabled: true)
        var statuses = service.observeStatus().makeAsyncIterator()
        let first = await statuses.next()
        #expect(first != nil && first != .unavailable)

        await service.setEnabled(false)
        var latest = first
        for _ in 0..<5 where latest != .off { latest = await statuses.next() }
        #expect(latest == .off)
        let state = try await devices.loadOrCreate(deviceName: "Test")
        #expect(state.preferences.syncEnabled == false)
    }
}
