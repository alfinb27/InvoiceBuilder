import Foundation

/// A catalogue price in a document's currency and price basis (`spec/documents.md` §3.1).
public enum LinePricing {
    public enum Failure: String, Error, Sendable {
        /// A foreign-currency document without an exchange rate cannot convert a home-currency price.
        case exchangeRateMissing = "exchange_rate_missing"
    }

    /// `round(price × b × c, amountMode)` with one division, so the only rounding is the final one.
    public static func unitPrice(item: CatalogItem, rate: TaxRate?, chargesTax: Bool, homeCurrency: CurrencyCode,
                                 documentCurrency: CurrencyCode, exchangeRate: String?, documentInclusive: Bool,
                                 currencies: CurrencyCatalog, mode: RoundingMode) -> Result<Int64, Failure> {
        var numerator = Decimal(1), denominator = Decimal(1)
        if chargesTax, item.priceIncludesTax != documentInclusive {
            let percent = rate.map(effectivePercent) ?? 0
            if item.priceIncludesTax {
                numerator = 100
                denominator = 100 + percent
            } else {
                numerator = 100 + percent
                denominator = 100
            }
        }
        if item.currency != documentCurrency {
            guard item.currency == homeCurrency, let text = exchangeRate?.trimmedOrNil,
                  let rate = DecimalString.parse(text), rate > 0 else {
                return .failure(.exchangeRateMissing)
            }
            numerator *= SpecMath.powerOfTen(currencies.exponent(of: documentCurrency)
                - currencies.exponent(of: homeCurrency))
            denominator *= rate
        }
        return .success(SpecMath.round(Decimal(item.unitPriceMinor) * numerator / denominator, mode))
    }

    /// `R`: a config rate's `percent`; a custom rate's components applied in order to 100, a compound component
    /// also taxing the earlier components' tax (5% + compound 10% → 15.5).
    public static func effectivePercent(of rate: TaxRate) -> Decimal {
        guard let components = rate.components, !components.isEmpty else {
            return rate.percent.flatMap(DecimalString.parse) ?? 0
        }
        var accumulated = Decimal(0)
        for component in components {
            let percent = DecimalString.parse(component.percent) ?? 0
            let base = Decimal(100) + ((component.compound ?? false) ? accumulated : 0)
            accumulated += base * percent / 100
        }
        return accumulated
    }
}
