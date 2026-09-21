import Foundation
import InvoiceCore
import InvoicePDF

/// Renders documents to PDF files and keeps them in the caches directory (`spec/pdf/RENDERING.md` §5). An issued
/// document never changes, so its file is written once; a draft's file is replaced whenever the draft is saved.
actor PDFLibrary {
    private let configs: TaxConfigStore
    private nonisolated let templates: PDFTemplateStore
    private let labels: PDFLabels
    private let reference: ReferenceData
    private let assets: any AssetRepository
    private let directory: URL

    init(configs: TaxConfigStore, reference: ReferenceData, assets: any AssetRepository,
         directory: URL? = nil) throws {
        self.configs = configs
        self.reference = reference
        self.assets = assets
        templates = try PDFTemplateStore.bundled()
        labels = try PDFLabels.bundled()
        let caches = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "InvoicePDFs")
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        self.directory = caches
    }

    /// The templates the switcher offers, in spec order.
    nonisolated var allTemplates: [PDFTemplate] { templates.all }

    /// A rendered file for `document`, from the cache when it is still valid.
    func file(for document: Document, business: Business, computed: ComputedDocument,
              template: TemplateID? = nil) async throws -> PDFFile {
        let templateID = template ?? document.templateId
        let url = directory.appending(path: name(for: document, business: business, template: templateID))
        if FileManager.default.fileExists(atPath: url.path) {
            return PDFFile(url: url, template: templateID)
        }
        let data = try await render(document: document, business: business, computed: computed,
                                    template: templateID)
        try data.write(to: url, options: .atomic)
        prune(keeping: url, documentID: document.id, template: templateID)
        trim(keeping: url)
        return PDFFile(url: url, template: templateID)
    }

    /// The bytes, without touching the cache (the live preview while a draft is being edited).
    func data(for document: Document, business: Business, computed: ComputedDocument,
              template: TemplateID? = nil) async throws -> Data {
        try await render(document: document, business: business, computed: computed,
                         template: template ?? document.templateId)
    }

    private func render(document: Document, business: Business, computed: ComputedDocument,
                        template: TemplateID) async throws -> Data {
        guard let config = configs.config(ref: document.taxConfigRef)
            ?? configs.latest(family: business.taxConfig, on: document.effectiveDate) else {
            throw SpecLoadingError(path: "tax/\(document.taxConfigRef)", reason: "no config for this document")
        }
        guard let layout = templates.template(template) else {
            throw SpecLoadingError(path: "pdf/layout/\(template.rawValue).json", reason: "template not bundled")
        }
        let model = PDFModelBuilder.build(document: document, computed: computed, config: config, labels: labels,
                                          reference: reference)
        let logoID = document.sellerSnapshot?.logoAssetId ?? business.logoAssetId
        let signatureID = document.sellerSnapshot?.signatureAssetId ?? business.signatureAssetId
        let request = PDFRenderRequest(
            model: model, template: layout, paperSize: config.paperSize, accentHex: business.accentColor,
            logo: try await assetData(logoID), signature: try await assetData(signatureID)
        )
        // Drawing is CPU work: keep it off the actor and off the main thread.
        return await Task.detached(priority: .userInitiated) { PDFRenderer.render(request) }.value
    }

    private func assetData(_ id: String?) async throws -> Data? {
        guard let id else { return nil }
        return try await assets.fetchAsset(id: id)?.data
    }

    /// Everything that changes the drawing goes into the file name — the document itself, not its `updatedAt`, so
    /// an unsaved edit can never be served from a stale file. The digest is FNV-1a rather than `hashValue`, which
    /// is seeded per process and would miss the cache on every launch.
    private func name(for document: Document, business: Business, template: TemplateID) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var key = (try? encoder.encode(document)) ?? Data(document.id.utf8)
        key.append(contentsOf: Array("|\(template.rawValue)|\(business.accentColor ?? "-")".utf8))
        key.append(contentsOf: Array("|\(business.logoAssetId ?? "-")|\(business.signatureAssetId ?? "-")".utf8))
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key {
            hash = (hash ^ UInt64(byte)) &* 0x1000_0000_01b3
        }
        return "\(prefix(document.id, template))\(String(hash, radix: 16)).pdf"
    }

    private func prefix(_ documentID: String, _ template: TemplateID) -> String {
        "\(documentID)-\(template.rawValue)-"
    }

    /// Drops the files this one replaces (an older revision, or a draft edited since) but keeps the other
    /// templates, so switching back and forth in the preview does not re-render.
    private func prune(keeping url: URL, documentID: String, template: TemplateID) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []
        let prefix = prefix(documentID, template)
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file != url {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Keeps the cache to `limit` files, oldest first. Every issued document would otherwise keep a file per
    /// template for ever; the system only empties the caches directory when the disk is under pressure.
    private func trim(keeping url: URL, limit: Int = 240) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: Array(keys))) ?? []
        guard files.count > limit else { return }
        let oldestFirst = files.filter { $0 != url }.sorted {
            let left = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            return left < right
        }
        for file in oldestFirst.prefix(files.count - limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Removes cached files for a document (a draft that was deleted, or a restore).
    func forget(documentID: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            ?? []
        for file in files where file.lastPathComponent.hasPrefix(documentID) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// A rendered PDF on disk: what the preview shows and what sharing and printing send.
struct PDFFile: Hashable, Sendable {
    let url: URL
    let template: TemplateID
}
