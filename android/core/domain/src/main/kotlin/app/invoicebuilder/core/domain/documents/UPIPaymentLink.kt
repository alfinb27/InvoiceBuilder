package app.invoicebuilder.core.domain.documents

import app.invoicebuilder.core.domain.decimal.MoneyInput
import app.invoicebuilder.core.domain.money.CurrencyCode
import app.invoicebuilder.core.domain.support.trimmedOrNull

/** UPI payment links for the PDF QR code (`spec/tax/ENGINE.md` §9). iOS: `UPIPaymentLink`. */
object UPIPaymentLink {
    /** Only for INR documents with a UPI ID and something left to pay. */
    fun applies(currency: CurrencyCode, vpa: String?, outstandingMinor: Long): Boolean =
        currency == CurrencyCode.INR && vpa?.trimmedOrNull != null && outstandingMinor > 0

    /**
     * `upi://pay?pa=<vpa>&pn=<payee name>&am=<amount>&cu=INR&tn=<invoice number>`; `am` has exactly two decimals and
     * no grouping; each value is percent-encoded as UTF-8, leaving only `A–Z a–z 0–9 - . _ ~` and `@` as they are.
     */
    fun url(vpa: String, payeeName: String, amountMinor: Long, invoiceNumber: String): String {
        val amount = MoneyInput.editingText(amountMinor, 2)
        return "upi://pay?pa=${encode(vpa)}&pn=${encode(payeeName)}&am=$amount&cu=INR&tn=${encode(invoiceNumber)}"
    }

    fun encode(value: String): String = buildString {
        for (byte in value.toByteArray(Charsets.UTF_8)) {
            val b = byte.toInt() and 0xFF
            val char = b.toChar()
            if (char in 'A'..'Z' || char in 'a'..'z' || char in '0'..'9' || char in "-._~@") append(char)
            else append('%').append("%02X".format(b))
        }
    }
}
