import InvoiceCore
import PencilKit
import SwiftUI

/// Draw a signature with a finger or Apple Pencil; saved as a transparent PNG (`spec/setup.md` §9).
struct SignaturePadSheet: View {
    let onSave: (ImagePayload) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pad = SignaturePadController()
    @State private var isSaving = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.l) {
                SignatureCanvas(controller: pad)
                    .frame(minHeight: 180, maxHeight: 280)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                    .overlay(alignment: .bottom) {
                        // A signing line, drawn under the ink.
                        Rectangle().fill(Color.gray.opacity(0.4)).frame(height: 1).padding(.horizontal, Theme.Space.xl)
                            .padding(.bottom, Theme.Space.xxl).allowsHitTesting(false)
                    }
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).stroke(Theme.border))
                    .accessibilityElement()
                    .accessibilityLabel("Signature pad")
                    .accessibilityHint("Draw your signature with a finger or Apple Pencil.")
                Text("Sign with your finger or Apple Pencil. It appears above \"Authorised signatory\" on your invoices.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                if failed { IssueText(message: "The signature couldn't be saved. Try again.") }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.l)
            .readableWidth()
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(pad.isEmpty || isSaving)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear", systemImage: "eraser", role: .destructive) { pad.clear() }
                        .labelStyle(.titleAndIcon)
                        .disabled(pad.isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            guard let payload = try pad.export() else { return }
            await onSave(payload)
            dismiss()
        } catch {
            failed = true
        }
    }
}

/// Owns the canvas so the sheet can clear and export it.
@MainActor @Observable
final class SignaturePadController {
    private(set) var isEmpty = true
    @ObservationIgnored fileprivate weak var canvas: PKCanvasView?

    func clear() {
        canvas?.drawing = PKDrawing()
        isEmpty = true
    }

    fileprivate func drawingChanged(_ drawing: PKDrawing) {
        isEmpty = drawing.strokes.isEmpty
    }

    /// The ink cropped to its bounds plus 8 px, at most 1024 px on its longest side, dark ink on transparent.
    func export() throws -> ImagePayload? {
        guard let drawing = canvas?.drawing, !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds
        let longest = max(bounds.width, bounds.height, 1)
        let scale = min(3, (CGFloat(ImageProcessing.maxPixelSize) - 16) / longest)
        let rect = bounds.insetBy(dx: -8 / scale, dy: -8 / scale)
        var image: UIImage?
        // Render with light traits so black ink stays black even when the device is in Dark Mode.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        guard let cgImage = image?.cgImage else { throw ImageProcessing.UnreadableImage() }
        return try ImageProcessing.signature(from: cgImage)
    }
}

private struct SignatureCanvas: UIViewRepresentable {
    let controller: SignaturePadController

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput // finger on iPhone, finger or Pencil on iPad
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate = context.coordinator
        controller.canvas = canvas
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        controller.canvas = canvas
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: SignaturePadController

        init(controller: SignaturePadController) {
            self.controller = controller
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.drawingChanged(canvasView.drawing)
        }
    }
}
