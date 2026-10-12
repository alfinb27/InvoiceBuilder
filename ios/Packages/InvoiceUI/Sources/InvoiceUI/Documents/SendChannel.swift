import InvoiceCore
import MessageUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// How Review & send hands the PDF over (`spec/documents.md` §8). iOS can't give a PDF to one chosen app, so
/// WhatsApp opens the share sheet (WhatsApp is one tap there).
enum SendChannel: String, CaseIterable, Identifiable, Sendable {
    case whatsApp, email, print, savePDF

    var id: String { rawValue }

    /// The tile's label.
    var label: String {
        switch self {
        case .whatsApp: "WhatsApp"
        case .email: "Email"
        case .print: "Print"
        case .savePDF: "Save PDF"
        }
    }

    /// The Review & send button for this channel.
    func buttonTitle(for docType: DocumentType) -> String {
        switch self {
        case .whatsApp: "Send on WhatsApp"
        case .email: "Send by email"
        case .print: "Print \(DocumentText.noun(docType))"
        case .savePDF: "Save as PDF"
        }
    }

    var symbol: String {
        switch self {
        case .whatsApp: "message"
        case .email: "envelope"
        case .print: "printer"
        case .savePDF: "arrow.down.doc"
        }
    }
}

/// The system mail composer and the "save to Files" picker, presented over whatever is on screen; each reports
/// whether the PDF really left the app (so "Mark as sent?" is only asked then).
extension SystemSheets {
    /// Mail with the PDF attached and the client's address filled in; false when this device can't send mail
    /// (the caller then uses the share sheet).
    static func email(_ url: URL, to recipient: String?, subject: String, completion: @escaping (Bool) -> Void)
        -> Bool {
        guard MFMailComposeViewController.canSendMail(), let data = try? Data(contentsOf: url),
              let presenter = topViewController else { return false }
        let mail = MFMailComposeViewController()
        let delegate = MailDelegate(completion: completion)
        mail.mailComposeDelegate = delegate
        objc_setAssociatedObject(mail, &MailDelegate.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if let recipient, !recipient.isEmpty { mail.setToRecipients([recipient]) }
        mail.setSubject(subject)
        mail.addAttachmentData(data, mimeType: "application/pdf", fileName: url.lastPathComponent)
        presenter.present(mail, animated: true)
        return true
    }

    /// The Files "Save" picker for a copy of the PDF.
    static func saveToFiles(_ url: URL, completion: @escaping (Bool) -> Void) {
        guard let presenter = topViewController else { return }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        let delegate = ExportDelegate(completion: completion)
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &ExportDelegate.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        presenter.present(picker, animated: true)
    }
}

@MainActor
private final class MailDelegate: NSObject, @preconcurrency MFMailComposeViewControllerDelegate {
    nonisolated(unsafe) static var key: UInt8 = 0
    let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult,
                               error: (any Error)?) {
        controller.dismiss(animated: true)
        completion(result == .sent)
    }
}

@MainActor
private final class ExportDelegate: NSObject, UIDocumentPickerDelegate {
    nonisolated(unsafe) static var key: UInt8 = 0
    let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(false)
    }
}
