/// UPI payment links for the PDF QR code (`spec/tax/ENGINE.md` §9).
public enum UPIPaymentLink {
    /// Only for INR documents with a UPI ID and something left to pay.
    public static func applies(currency: CurrencyCode, vpa: String?, outstandingMinor: Int64) -> Bool {
        currency == .inr && vpa?.trimmedOrNil != nil && outstandingMinor > 0
    }

    /// `upi://pay?pa=<vpa>&pn=<payee name>&am=<amount>&cu=INR&tn=<invoice number>`; `am` has exactly two
    /// decimals and no grouping; each value is percent-encoded as UTF-8, leaving only `A–Z a–z 0–9 - . _ ~` and `@`
    /// as they are.
    public static func url(vpa: String, payeeName: String, amountMinor: Int64, invoiceNumber: String) -> String {
        let amount = MoneyInput.editingText(minor: amountMinor, exponent: 2)
        return "upi://pay?pa=\(encode(vpa))&pn=\(encode(payeeName))&am=\(amount)&cu=INR&tn=\(encode(invoiceNumber))"
    }

    static func encode(_ value: String) -> String {
        var output = ""
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"),
                 UInt8(ascii: "~"), UInt8(ascii: "@"):
                output.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                let hex = String(byte, radix: 16, uppercase: true)
                output += "%" + (hex.count == 1 ? "0" + hex : hex)
            }
        }
        return output
    }
}
