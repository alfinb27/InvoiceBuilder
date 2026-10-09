import InvoiceCore
import PhotosUI
import SwiftUI

/// Logo and signature pickers, shared by onboarding (kept in memory until Finish) and Settings (saved at once).
struct ImagesFormSections: View {
    let logo: Data?
    let signature: Data?
    let isBusy: Bool
    /// India: GST Rule 46 asks for a signature on tax invoices.
    let signatureNote: String?
    let onPickLogo: (Data) async -> Void
    let onRemoveLogo: () async -> Void
    let onSaveSignature: (ImagePayload) async -> Void
    let onRemoveSignature: () async -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showingSignaturePad = false

    var body: some View {
        Section {
            HStack(spacing: Theme.Space.l) {
                ImageWell(data: logo, placeholder: "photo", label: "Logo")
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label(logo == nil ? "Choose logo" : "Replace logo", systemImage: "photo.on.rectangle")
                    }
                    if logo != nil {
                        Button("Remove logo", systemImage: "trash", role: .destructive) {
                            Task { await onRemoveLogo() }
                        }
                    }
                }
                .disabled(isBusy)
                if isBusy { ProgressView() }
            }
        } header: {
            Text("Logo")
        } footer: {
            Text("Shown at the top of your invoices. Large images are resized to 1024 pixels.")
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await onPickLogo(data)
                }
                photoItem = nil
            }
        }

        Section {
            HStack(spacing: Theme.Space.l) {
                ImageWell(data: signature, placeholder: "signature", label: "Signature")
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Button(signature == nil ? "Draw signature" : "Draw again", systemImage: "pencil.and.scribble") {
                        showingSignaturePad = true
                    }
                    if signature != nil {
                        Button("Remove signature", systemImage: "trash", role: .destructive) {
                            Task { await onRemoveSignature() }
                        }
                    }
                }
                .disabled(isBusy)
            }
        } header: {
            Text("Signature")
        } footer: {
            Text(signatureNote ?? "Printed above \"Authorised signatory\" on your invoices.")
        }
        .sheet(isPresented: $showingSignaturePad) {
            SignaturePadSheet(onSave: onSaveSignature)
        }
    }
}

/// A square preview of a stored image, or a placeholder symbol.
struct ImageWell: View {
    let data: Data?
    let placeholder: String
    let label: String

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(Theme.Space.xs)
                    .background(Color.white) // images are shown on white, as on paper
            } else {
                Image(systemName: placeholder)
                    .font(Theme.Fonts.title3)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surfaceMuted)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).stroke(Theme.border))
        .accessibilityElement()
        .accessibilityLabel(data == nil ? "No \(label.lowercased())" : "\(label) preview")
    }
}

/// Loads a stored asset's bytes for display.
struct StoredAssetLoader: ViewModifier {
    let assetID: String?
    let assets: any AssetRepository
    @Binding var data: Data?

    func body(content: Content) -> some View {
        content.task(id: assetID) {
            guard let assetID else {
                data = nil
                return
            }
            data = try? await assets.fetchAsset(id: assetID)?.data
        }
    }
}
