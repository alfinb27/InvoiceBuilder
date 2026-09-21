import Foundation
import InvoiceCore
import PDFKit
import Testing
@testable import InvoiceUI

/// The preview screen and the file cache behind it (`spec/pdf/RENDERING.md` §5, `spec/documents.md` §8). What the
/// page *says* is covered by the `pdf` fixtures in InvoiceCore; these tests are about rendering, caching and the
/// mark-as-sent prompt.
@MainActor
@Suite("Document preview")
struct DocumentPreviewTests {
    /// A draft with a client and one line, ready to render.
    func draft(_ session: Session) async throws -> DocumentViewModel {
        let model = DocumentViewModel(session: session, route: .new(.invoice, id: "doc-1"), autosaveDelay: .zero)
        await model.load()
        let clients = try await firstValue(session.dependencies.clients.observeClients(businessID: session.business.id))
        model.chooseClient(try #require(clients?.first { $0.name == "Rao Traders" }))
        let items = try await firstValue(session.dependencies.catalog.observeItems(businessID: session.business.id))
        model.addItem(try #require(items?.first { $0.name == "Website development" }))
        return model
    }

    /// The extracted text, with the line breaks the page layout introduced collapsed to single spaces, so an
    /// assertion does not depend on where a cell happens to wrap.
    func text(of url: URL) throws -> String {
        let document = try #require(PDFDocument(url: url))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: " ")
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @Test func aDraftPreviewRendersTheWatermarkedInvoiceAndIsSavedOnce() async throws {
        let session = try await TestEnvironment.session()
        let model = try await draft(session)
        await model.openPreview()
        let preview = try #require(model.preview)
        await preview.render()

        let file = try #require(preview.state.file)
        let text = try text(of: file)
        #expect(text.contains("DRAFT"), "an unissued document is watermarked")
        #expect(text.contains("Rao Traders") && text.contains("Website development"))
        #expect(text.contains("₹5,900.00"), "the total comes from the engine")

        // The second render is served from the cache: same URL, same file, untouched.
        let written = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        await preview.render()
        #expect(preview.state.file == file)
        let again = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        #expect(written == again)
    }

    @Test func editingTheDraftRendersAFreshFile() async throws {
        let session = try await TestEnvironment.session()
        let model = try await draft(session)
        await model.openPreview()
        let first = try #require(model.preview)
        await first.render()
        let before = try #require(first.state.file)

        model.setNotesText("Payable within 15 days")
        await model.flush()
        model.preview = nil
        await model.openPreview()
        let second = try #require(model.preview)
        await second.render()
        let after = try #require(second.state.file)

        #expect(after != before, "a changed draft must not be served from the old file")
        #expect(try text(of: after).contains("Payable within 15 days"))
    }

    @Test func switchingTemplateRendersThatTemplateAndKeepsBoth() async throws {
        let session = try await TestEnvironment.session()
        let model = try await draft(session)
        await model.openPreview()
        let preview = try #require(model.preview)
        await preview.render()
        let modern = try #require(preview.state.file) // the business's template
        #expect(preview.state.template == .modern)
        #expect(preview.templates.map(\.id.rawValue) == ["classic", "compact", "minimal", "modern"])

        await preview.setTemplate(.compact)
        let compact = try #require(preview.state.file)
        #expect(compact != modern && preview.state.template == .compact)
        #expect(FileManager.default.fileExists(atPath: modern.path), "the other template stays cached")
        #expect(try text(of: compact).contains("Rao Traders"))
    }

    @Test func sharingAnIssuedInvoiceOffersToMarkItSent() async throws {
        let session = try await TestEnvironment.session()
        let model = try await draft(session)
        await model.requestIssue()
        await model.confirmIssue()
        await model.openPreview()
        let preview = try #require(model.preview)
        await preview.render()
        #expect(try text(of: #require(preview.state.file)).contains("INV/26-27/0001"))
        #expect(try text(of: #require(preview.state.file)).contains("DRAFT") == false)

        #expect(preview.canMarkSent)
        preview.didShare()
        #expect(preview.state.askToMarkSent)
        await preview.markSent()

        let stored = try #require(try await session.dependencies.documents.fetchDocument(id: "doc-1"))
        #expect(stored.sentAt == 1_789_800_000_000)
        #expect(stored.status(today: TestEnvironment.today) == .sent)
        #expect(model.state.document.sentAt == stored.sentAt, "the document screen shows the new status")

        // Sharing it again is fine; it does not ask twice.
        preview.state.askToMarkSent = false
        preview.didShare()
        #expect(!preview.state.askToMarkSent && !preview.canMarkSent)
    }

    @Test func draftsAreNeverMarkedSent() async throws {
        let session = try await TestEnvironment.session()
        let model = try await draft(session)
        await model.openPreview()
        let preview = try #require(model.preview)
        #expect(!preview.canMarkSent)
        preview.didShare()
        #expect(!preview.state.askToMarkSent)
    }

    @Test func deletingADraftDropsItsRenderedFiles() async throws {
        let session = try await TestEnvironment.session()
        let model = try await draft(session)
        await model.openPreview()
        let preview = try #require(model.preview)
        await preview.render()
        let file = try #require(preview.state.file)
        #expect(FileManager.default.fileExists(atPath: file.path))

        await model.deleteDraft()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// The cache holds a file per document and template; it must not grow for ever.
    @Test func theCacheStaysBounded() async throws {
        let session = try await TestEnvironment.session()
        let model = try await draft(session)
        await model.openPreview()
        let preview = try #require(model.preview)
        await preview.render()
        let file = try #require(preview.state.file)
        let directory = file.deletingLastPathComponent()
        // Fill the cache past its limit with files that look older than the one just rendered.
        for index in 0..<260 {
            let stale = directory.appending(path: "old-\(index).pdf")
            try Data("x".utf8).write(to: stale)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)],
                                                  ofItemAtPath: stale.path)
        }
        model.setNotesText("Trigger another render")
        await model.flush()
        model.preview = nil
        await model.openPreview()
        await try #require(model.preview).render()

        let count = try FileManager.default.contentsOfDirectory(atPath: directory.path).count
        #expect(count <= 240, "the cache kept \(count) files")
        let newest = try #require(model.preview?.state.file)
        #expect(FileManager.default.fileExists(atPath: newest.path), "the file just rendered must survive")
    }

    @Test func aGBInvoiceRendersInPoundsWithItsOwnLabels() async throws {
        let session = try await TestEnvironment.session(.uk)
        let model = DocumentViewModel(session: session, route: .new(.invoice, id: "doc-1"), autosaveDelay: .zero)
        await model.load()
        let clients = try await firstValue(session.dependencies.clients.observeClients(businessID: session.business.id))
        model.chooseClient(try #require(clients?.first))
        let items = try await firstValue(session.dependencies.catalog.observeItems(businessID: session.business.id))
        model.addItem(try #require(items?.first))
        await model.openPreview()
        let preview = try #require(model.preview)
        await preview.render()

        let text = try text(of: #require(preview.state.file))
        #expect(text.contains("VAT"))
        #expect(text.contains("£"))
        #expect(!text.contains("GSTIN"))
    }
}
