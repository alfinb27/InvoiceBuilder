import Foundation

/// `TaxEngine.compute(input) → ComputedDocument` (`spec/tax/ENGINE.md` §3): a pure function (no clock, locale or I/O)
/// that interprets a country's tax config. Each step below is one numbered step of the spec.
public enum TaxEngine {
    public static func compute(_ input: EngineInput) throws(TaxEngineError) -> ComputedDocument {
        var computation = try Computation(input)
        try computation.run()
        return computation.output()
    }
}

/// A line or shipping pseudo-line on its way through the steps ("tax unit").
private struct TaxUnit {
    var amount: Int64
    var discount: Int64 = 0
    var net: Int64
    var rate: TaxRate
    var isShipping: Bool
    var productCode: String?
    var components: [TaxComponent] = []
    var totalPercent: Decimal = 0
    var taxes: [Int64] = []
    var taxable: Int64 = 0
}

private struct TaxComponent {
    /// Nil for a non-tax group (exempt, nil-rated, outside scope).
    var code: String?
    var percent: Decimal
    var category: TaxCategory
    var compound: Bool

    var key: TaxLineKey { TaxLineKey(code: code, rate: DecimalString.string(from: percent), category: category) }
}

private struct TaxLineKey: Hashable {
    var code: String?
    var rate: String
    var category: TaxCategory
}

private struct Computation {
    static let nonTaxCategories: Set<TaxCategory> = [.exempt, .nilRated, .outsideScope]
    static let hundred = Decimal(100)

    let input: EngineInput
    var config: TaxConfig { input.config }
    var draft: EngineDraft { input.draft }
    var seller: EngineSeller { input.seller }
    var buyer: EngineBuyer { input.buyer }

    // Step 0: context
    let registration: TaxRegistration
    let chargesTax: Bool
    let effectiveDate: LocalDate
    let sellerRegion: String?
    let placeOfSupply: String?
    let sameRegion: Bool
    let foreignCurrency: Bool
    let reverseCharge: Bool
    let inclusive: Bool
    let buyerHasTaxID: Bool

    // Step 1
    var rule: ComponentRule?

    var lines: [TaxUnit] = []
    var shipping: [TaxUnit] = []
    var staleRateLines: [Int] = []
    var subtotal: Int64 = 0
    var discountTotal: Int64 = 0
    var shippingTotal: Int64 = 0
    var taxLines: [ComputedTaxLine] = []
    var totals = ComputedTotals(subtotal: 0, discount: 0, shipping: 0, taxable: 0, tax: 0, taxNotCharged: 0,
                                roundOff: 0, total: 0)
    var home: HomeTotals?
    var notes: [ComputedNote] = []
    var issues: [EngineIssue] = []

    init(_ input: EngineInput) throws(TaxEngineError) {
        self.input = input
        let config = input.config, seller = input.seller, buyer = input.buyer, draft = input.draft
        guard let registration = config.registration(seller.registration) else { throw TaxEngineError(.invalidInput) }
        self.registration = registration
        chargesTax = registration.chargesTax
        effectiveDate = draft.supplyDate ?? draft.issueDate

        if let region = seller.region?.trimmedOrNil {
            sellerRegion = region
        } else if let length = config.taxIDFormat?.regionFromPrefix, let taxID = seller.taxId?.trimmedOrNil,
                  taxID.count >= length {
            sellerRegion = String(taxID.prefix(length))
        } else {
            sellerRegion = nil
        }

        if config.regions.isEmpty {
            placeOfSupply = nil
        } else if let override = draft.placeOfSupply?.trimmedOrNil {
            placeOfSupply = override
        } else if let country = buyer.country?.trimmedOrNil, country != config.country {
            placeOfSupply = config.foreignRegion // an explicit foreign country only; no country means domestic
        } else {
            placeOfSupply = buyer.region?.trimmedOrNil ?? sellerRegion
        }
        sameRegion = placeOfSupply != nil && placeOfSupply == sellerRegion
        foreignCurrency = draft.currency != seller.homeCurrency
        reverseCharge = draft.reverseCharge && config.reverseCharge.supported && chargesTax
        inclusive = draft.pricesIncludeTax && chargesTax && !reverseCharge
        buyerHasTaxID = buyer.taxId?.trimmedOrNil != nil
    }

    mutating func run() throws(TaxEngineError) {
        try selectRule()
        try computeLineAmounts()
        try allocateInvoiceDiscount()
        try splitShipping()
        try assignComponents()
        computeTaxes()
        collectTaxLines()
        try computeTotals()
        collectNotes()
        runChecks()
    }

    // MARK: Step 1: component rule

    mutating func selectRule() throws(TaxEngineError) {
        guard chargesTax else { return }
        guard let rule = config.componentRules.first(where: { matches($0.when, total: nil) }) else {
            throw TaxEngineError(.noComponentRule)
        }
        self.rule = rule
    }

    /// Every key the condition lists must match; list keys match when the value is in the list.
    func matches(_ condition: TaxCondition, total: Int64?) -> Bool {
        if let list = condition.supplyType, !list.contains(draft.supplyType) { return false }
        if let value = condition.sameRegion, value != sameRegion { return false }
        if let list = condition.sellerRegistration, !list.contains(seller.registration) { return false }
        if let value = condition.buyerIsBusiness, value != buyer.isBusiness { return false }
        if let value = condition.buyerHasTaxId, value != buyerHasTaxID { return false }
        if let value = condition.reverseCharge, value != reverseCharge { return false }
        if let list = condition.docType, !list.contains(draft.docType.rawValue) { return false }
        if let value = condition.foreignCurrency, value != foreignCurrency { return false }
        if let minimum = condition.totalAtLeastMinor {
            guard let total, total >= minimum else { return false }
        }
        return true
    }

    // MARK: Step 2: line amounts

    mutating func computeLineAmounts() throws(TaxEngineError) {
        let rates = config.availableRates(customRates: seller.customRates)
        for (index, line) in draft.lines.enumerated() {
            guard let quantity = DecimalString.parse(line.quantity), quantity >= 0, line.unitPrice >= 0 else {
                throw TaxEngineError(.invalidInput, line: index)
            }
            let gross = quantity * Decimal(line.unitPrice)
            let lineDiscount: Decimal
            switch line.discount {
            case .percent(let text)?:
                guard let percent = DecimalString.parse(text), percent >= 0 else {
                    throw TaxEngineError(.invalidInput, line: index)
                }
                lineDiscount = gross * percent / Self.hundred
            case .amount(let value)?:
                guard value >= 0 else { throw TaxEngineError(.invalidInput, line: index) }
                lineDiscount = Decimal(value)
            case nil:
                lineDiscount = 0
            }
            guard lineDiscount <= gross else { throw TaxEngineError(.lineDiscountExceedsAmount, line: index) }
            guard let rate = rates.first(where: { $0.id == line.rateId }) else {
                throw TaxEngineError(.unknownRate, line: index)
            }
            if !rate.isInForce(on: effectiveDate) { staleRateLines.append(index) }
            let amount = SpecMath.round(gross - lineDiscount, config.rounding.amountMode)
            lines.append(TaxUnit(amount: amount, net: amount, rate: rate, isShipping: false,
                                 productCode: line.productCode))
        }
        subtotal = lines.reduce(0) { $0 + $1.amount }
    }

    // MARK: Step 3: invoice discount

    mutating func allocateInvoiceDiscount() throws(TaxEngineError) {
        switch draft.discount {
        case .percent(let text)?:
            guard let percent = DecimalString.parse(text), percent >= 0 else { throw TaxEngineError(.invalidInput) }
            discountTotal = SpecMath.round(Decimal(subtotal) * percent / Self.hundred, config.rounding.amountMode)
        case .amount(let value)?:
            guard value >= 0 else { throw TaxEngineError(.invalidInput) }
            discountTotal = value
        case nil:
            discountTotal = 0
        }
        guard discountTotal <= subtotal else { throw TaxEngineError(.discountExceedsSubtotal) }
        let shares = SpecMath.allocateProportional(discountTotal, lines.map(\.amount))
        for index in lines.indices {
            lines[index].discount = shares[index]
            lines[index].net = lines[index].amount - shares[index]
        }
    }

    // MARK: Step 4: shipping

    mutating func splitShipping() throws(TaxEngineError) {
        shippingTotal = draft.shipping ?? 0
        guard shippingTotal >= 0 else { throw TaxEngineError(.invalidInput) }
        guard shippingTotal > 0 else { return }
        guard !lines.isEmpty else { throw TaxEngineError(.invalidInput) } // shipping takes its rate from the lines
        switch config.shipping.rule {
        case .principalSupplyRate:
            // The line with the largest net amount; ties go to the lowest index.
            var principal = 0
            for index in lines.indices where lines[index].net > lines[principal].net { principal = index }
            shipping = [TaxUnit(amount: shippingTotal, net: shippingTotal, rate: lines[principal].rate,
                                isShipping: true)]
        case .apportion:
            var groups: [(rate: TaxRate, weight: Int64)] = []
            for line in lines {
                if let index = groups.firstIndex(where: { $0.rate.id == line.rate.id }) {
                    groups[index].weight += line.net
                } else {
                    groups.append((line.rate, line.net))
                }
            }
            let parts = SpecMath.allocateProportional(shippingTotal, groups.map(\.weight))
            shipping = zip(groups, parts).compactMap { group, part in
                part > 0 ? TaxUnit(amount: part, net: part, rate: group.rate, isShipping: true) : nil
            }
        }
    }

    // MARK: Step 5: components per line

    mutating func assignComponents() throws(TaxEngineError) {
        guard chargesTax, let rule else { return }
        for index in lines.indices {
            lines[index].components = try components(for: lines[index].rate, rule: rule, line: index)
            lines[index].totalPercent = lines[index].components.reduce(0) { $0 + $1.percent }
        }
        for index in shipping.indices {
            shipping[index].components = try components(for: shipping[index].rate, rule: rule, line: nil)
            shipping[index].totalPercent = shipping[index].components.reduce(0) { $0 + $1.percent }
        }
    }

    func components(for rate: TaxRate, rule: ComponentRule, line: Int?) throws(TaxEngineError) -> [TaxComponent] {
        var components: [TaxComponent] = []
        switch rule.components {
        case .fromRate:
            for component in rate.components ?? [] {
                guard let percent = DecimalString.parse(component.percent) else {
                    throw TaxEngineError(.invalidInput, line: line)
                }
                components.append(TaxComponent(code: component.code, percent: percent, category: rate.category,
                                               compound: component.compound ?? false))
            }
        case .list(let references):
            for reference in references {
                var code = reference.code
                if code == "$localComponent" {
                    guard let placeOfSupply, let local = config.region(placeOfSupply)?.localComponent else {
                        throw TaxEngineError(.unknownRegion, line: line)
                    }
                    code = local
                }
                let percent: Decimal
                if let override = reference.rateOverride {
                    guard let value = DecimalString.parse(override) else {
                        throw TaxEngineError(.invalidInput, line: line)
                    }
                    percent = value
                } else {
                    guard let ratePercent = rate.percent.flatMap(DecimalString.parse),
                          let share = DecimalString.parse(reference.share) else {
                        throw TaxEngineError(.invalidInput, line: line)
                    }
                    percent = ratePercent * share
                }
                components.append(TaxComponent(code: code, percent: percent,
                                               category: reference.categoryOverride ?? rate.category, compound: false))
            }
        }
        // Exempt, nil-rated and outside-scope supplies carry no tax: one non-tax group instead of components.
        if let nonTax = components.first(where: { Self.nonTaxCategories.contains($0.category) }) {
            return [TaxComponent(code: nil, percent: 0, category: nonTax.category, compound: false)]
        }
        if inclusive, components.contains(where: \.compound) {
            throw TaxEngineError(.inclusiveCompoundUnsupported, line: line)
        }
        return components
    }

    // MARK: Step 6: taxable value and tax

    mutating func computeTaxes() {
        guard chargesTax else {
            for index in lines.indices { lines[index].taxable = lines[index].net }
            for index in shipping.indices { shipping[index].taxable = shipping[index].net }
            return
        }
        switch config.rounding.taxLevel {
        case .line:
            for index in lines.indices { taxLine(&lines[index]) }
            for index in shipping.indices { taxLine(&shipping[index]) }
        case .invoice:
            if inclusive { taxInvoiceInclusive() } else { taxInvoiceExclusive() }
        }
    }

    /// Line level: each line (and shipping pseudo-line) is rounded on its own.
    func taxLine(_ unit: inout TaxUnit) {
        let mode = config.rounding.taxMode
        unit.taxes = []
        if inclusive {
            let divisor = Self.hundred + unit.totalPercent
            for component in unit.components {
                unit.taxes.append(SpecMath.round(Decimal(unit.net) * component.percent / divisor, mode))
            }
            unit.taxable = unit.net - unit.taxes.reduce(0, +)
        } else {
            unit.taxable = unit.net
            var accumulated: Int64 = 0
            for component in unit.components {
                let base = Decimal(unit.taxable) + (component.compound ? Decimal(accumulated) : 0)
                let tax = SpecMath.round(base * component.percent / Self.hundred, mode)
                unit.taxes.append(tax)
                accumulated += tax
            }
        }
    }

    /// Invoice level, exclusive prices: exact tax per group, rounded once per component code across the invoice.
    mutating func taxInvoiceExclusive() {
        for index in lines.indices { lines[index].taxable = lines[index].net }
        for index in shipping.indices { shipping[index].taxable = shipping[index].net }
        var groups: [(key: TaxLineKey, component: TaxComponent, taxable: Int64)] = []
        for unit in lines + shipping {
            for component in unit.components {
                if let index = groups.firstIndex(where: { $0.key == component.key }) {
                    groups[index].taxable += unit.taxable
                } else {
                    groups.append((component.key, component, unit.taxable))
                }
            }
        }
        let exacts = groups.map { Decimal($0.taxable) * $0.component.percent / Self.hundred }
        var taxes = Array(repeating: Int64(0), count: groups.count)
        for code in orderedCodes(groups.map(\.component.code)) {
            let members = groups.indices.filter { groups[$0].component.code == code }
            let total = SpecMath.round(members.reduce(Decimal(0)) { $0 + exacts[$1] }, config.rounding.taxMode)
            for (member, part) in zip(members, SpecMath.distribute(total, members.map { exacts[$0] })) {
                taxes[member] = part
            }
        }
        invoiceTaxLines = zip(groups, taxes).map { group, tax in
            (group.key, group.taxable, group.component.code == nil ? 0 : tax)
        }
    }

    /// Invoice level, inclusive prices: lines grouped by identical component set; the typed totals are kept exactly.
    mutating func taxInvoiceInclusive() {
        struct Group {
            var keys: [TaxLineKey]
            var components: [TaxComponent]
            var totalPercent: Decimal
            var members: [(isShipping: Bool, index: Int)]
            var inclusiveTotal: Int64 = 0
            var exacts: [Decimal] = []
            var taxes: [Int64] = []
        }
        var groups: [Group] = []
        let units = lines.indices.map { (false, $0) } + shipping.indices.map { (true, $0) }
        for (isShipping, index) in units {
            let unit = isShipping ? shipping[index] : lines[index]
            let keys = unit.components.map(\.key)
            if let position = groups.firstIndex(where: { $0.keys == keys }) {
                groups[position].members.append((isShipping, index))
            } else {
                groups.append(Group(keys: keys, components: unit.components, totalPercent: unit.totalPercent,
                                    members: [(isShipping, index)]))
            }
        }
        for position in groups.indices {
            let total = groups[position].members.reduce(Int64(0)) { sum, member in
                sum + (member.isShipping ? shipping[member.index] : lines[member.index]).net
            }
            groups[position].inclusiveTotal = total
            let divisor = Self.hundred + groups[position].totalPercent
            groups[position].exacts = groups[position].components.map { Decimal(total) * $0.percent / divisor }
            groups[position].taxes = Array(repeating: 0, count: groups[position].components.count)
        }
        let codes = orderedCodes(groups.flatMap { $0.components.map(\.code) })
        for code in codes {
            var members: [(group: Int, component: Int)] = []
            for (groupIndex, group) in groups.enumerated() {
                for (componentIndex, component) in group.components.enumerated() where component.code == code {
                    members.append((groupIndex, componentIndex))
                }
            }
            let exacts = members.map { groups[$0.group].exacts[$0.component] }
            let total = SpecMath.round(exacts.reduce(0, +), config.rounding.taxMode)
            for (member, part) in zip(members, SpecMath.distribute(total, exacts)) {
                groups[member.group].taxes[member.component] = part
            }
        }
        var taxLines: [(TaxLineKey, Int64, Int64)] = []
        for group in groups {
            let groupTax = group.taxes.reduce(0, +)
            // For display, the group's tax is split across its lines in proportion to their net amounts.
            let divisor = Self.hundred + group.totalPercent
            let shares = group.totalPercent == 0
                ? Array(repeating: Int64(0), count: group.members.count)
                : SpecMath.distribute(groupTax, group.members.map { member in
                    let net = (member.isShipping ? shipping[member.index] : lines[member.index]).net
                    return Decimal(net) * group.totalPercent / divisor
                })
            for (member, share) in zip(group.members, shares) {
                if member.isShipping {
                    shipping[member.index].taxable = shipping[member.index].net - share
                } else {
                    lines[member.index].taxable = lines[member.index].net - share
                }
            }
            let groupTaxable = group.inclusiveTotal - groupTax
            for (key, tax) in zip(group.keys, group.taxes) {
                taxLines.append((key, groupTaxable, key.code == nil ? 0 : tax))
            }
        }
        invoiceTaxLines = taxLines
    }

    /// Component codes in order of first appearance.
    func orderedCodes(_ codes: [String?]) -> [String?] {
        var seen: [String?] = []
        for code in codes where !seen.contains(code) { seen.append(code) }
        return seen
    }

    /// Invoice-level results waiting to be aggregated in Step 7: (key, taxable, tax).
    var invoiceTaxLines: [(TaxLineKey, Int64, Int64)] = []

    // MARK: Step 7: tax lines

    mutating func collectTaxLines() {
        guard chargesTax else { return }
        var entries: [(key: TaxLineKey, taxable: Int64, tax: Int64)] = []
        switch config.rounding.taxLevel {
        case .line:
            for unit in lines + shipping {
                for (component, tax) in zip(unit.components, unit.taxes) {
                    entries.append((component.key, unit.taxable, component.code == nil ? 0 : tax))
                }
            }
        case .invoice:
            entries = invoiceTaxLines.map { ($0.0, $0.1, $0.2) }
        }
        let charged = !reverseCharge
        for entry in entries {
            if let index = taxLines.firstIndex(where: {
                $0.component == entry.key.code && $0.rate == entry.key.rate && $0.category == entry.key.category
            }) {
                taxLines[index].taxable += entry.taxable
                taxLines[index].tax += entry.tax
            } else {
                taxLines.append(ComputedTaxLine(component: entry.key.code, rate: entry.key.rate,
                                                category: entry.key.category, taxable: entry.taxable,
                                                tax: entry.tax, charged: charged, homeTax: nil))
            }
        }
    }

    // MARK: Steps 8–9: totals and home currency

    mutating func computeTotals() throws(TaxEngineError) {
        let taxable = (lines + shipping).reduce(Int64(0)) { $0 + $1.taxable }
        let tax = taxLines.filter(\.charged).reduce(Int64(0)) { $0 + $1.tax }
        let taxNotCharged = taxLines.filter { !$0.charged }.reduce(Int64(0)) { $0 + $1.tax }
        var roundOff: Int64 = 0
        if let grandTotal = config.rounding.grandTotal, draft.roundOff ?? grandTotal.defaultOn, grandTotal.roundToMinor > 0 {
            let beforeRounding = taxable + tax
            let rounded = SpecMath.round(Decimal(beforeRounding) / Decimal(grandTotal.roundToMinor), grandTotal.mode)
                * grandTotal.roundToMinor
            roundOff = rounded - beforeRounding
        }
        totals = ComputedTotals(subtotal: subtotal, discount: discountTotal, shipping: shippingTotal, taxable: taxable,
                                tax: tax, taxNotCharged: taxNotCharged, roundOff: roundOff,
                                total: taxable + tax + roundOff)

        guard foreignCurrency, config.foreignCurrency.homeTotals, let rateText = draft.exchangeRate?.trimmedOrNil else {
            return
        }
        guard let rate = DecimalString.parse(rateText), rate > 0 else { throw TaxEngineError(.invalidInput) }
        let scale = SpecMath.powerOfTen(input.currencies.exponent(of: seller.homeCurrency)
            - input.currencies.exponent(of: draft.currency))
        let mode = config.rounding.amountMode
        let convert = { (amount: Int64) in SpecMath.round(Decimal(amount) * rate * scale, mode) }
        home = HomeTotals(currency: seller.homeCurrency, rate: rateText, taxable: convert(taxable), tax: convert(tax),
                          total: convert(totals.total))
        if config.foreignCurrency.taxInHomeCurrency {
            for index in taxLines.indices { taxLines[index].homeTax = convert(taxLines[index].tax) }
        }
    }

    // MARK: Step 10: notes

    mutating func collectNotes() {
        var ids = registration.notes ?? []
        if chargesTax { ids += rule?.notes ?? [] }
        if reverseCharge { ids += config.reverseCharge.notes ?? [] }
        var seen: Set<String> = []
        for id in ids where seen.insert(id).inserted {
            if let note = config.notesCatalog[id] {
                notes.append(ComputedNote(id: id, text: note.text, placement: note.placement))
            }
        }
    }

    // MARK: Step 12: checks → issues

    mutating func runChecks() {
        if !staleRateLines.isEmpty {
            issues.append(EngineIssue(code: "rate_not_effective", severity: .warning, lines: staleRateLines))
        }
        let comparedTotal = foreignCurrency ? home?.total : totals.total
        for check in config.checks {
            guard matches(check.when ?? .always, total: comparedTotal) else { continue }
            let severity = EngineIssue.Severity(rawValue: check.severity)
            switch check.type ?? "require" {
            case "require":
                if (check.require ?? []).contains(where: { field($0)?.trimmedOrNil == nil }) {
                    issues.append(EngineIssue(code: check.code, severity: severity))
                }
            case "productCodeDigits":
                guard let tiers = config.productCodes?.tiers, let first = tiers.first else { continue }
                let tier = seller.turnoverMinor.map { turnover in
                    tiers.first { $0.maxTurnoverMinor.map { $0 >= turnover } ?? true } ?? tiers[tiers.count - 1]
                } ?? first
                let required = buyerHasTaxID ? tier.b2bDigits : tier.b2cDigits
                guard required > 0 else { continue }
                let short = lines.indices.filter { digitCount(lines[$0].productCode) < required }
                if !short.isEmpty { issues.append(EngineIssue(code: check.code, severity: severity, lines: short)) }
            default:
                continue
            }
        }
    }

    func field(_ path: String) -> String? {
        switch path {
        case "seller.taxId": seller.taxId
        case "seller.lutReference": seller.lutReference
        case "seller.address": seller.address
        case "buyer.name": buyer.name
        case "buyer.address": buyer.address
        case "buyer.region": buyer.region
        case "buyer.taxId": buyer.taxId
        case "buyer.country": buyer.country
        case "draft.exchangeRate": draft.exchangeRate
        case "draft.dueDate": draft.dueDate?.iso
        default: nil
        }
    }

    func digitCount(_ code: String?) -> Int {
        (code ?? "").utf8.filter { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }.count
    }

    // MARK: Step 11 and output

    func title() -> String {
        guard draft.docType != .quote else { return registration.titles.quote }
        if let allExempt = registration.titles.invoiceAllExempt, chargesTax,
           lines.allSatisfy({ line in
               line.components.count == 1 && line.components[0].code == nil
                   && [TaxCategory.exempt, .nilRated].contains(line.components[0].category)
           }) {
            return allExempt
        }
        return registration.titles.invoice
    }

    func output() -> ComputedDocument {
        let lineTaxes = chargesTax && config.rounding.taxLevel == .line
        let computedLines = lines.map { line in
            ComputedLine(
                amount: line.amount, discount: line.discount, taxable: line.taxable, rateId: line.rate.id,
                rate: chargesTax ? DecimalString.string(from: line.totalPercent) : "0",
                category: chargesTax ? (line.components.first?.category ?? line.rate.category) : line.rate.category,
                taxes: lineTaxes ? zip(line.components, line.taxes).map { component, tax in
                    LineTax(component: component.code, rate: DecimalString.string(from: component.percent),
                            amount: component.code == nil ? 0 : tax)
                } : nil
            )
        }
        let computedShipping = shippingTotal > 0 ? ComputedShipping(
            amount: shippingTotal, taxable: shipping.reduce(0) { $0 + $1.taxable },
            parts: shipping.map { ShippingPart(rateId: $0.rate.id, amount: $0.amount, taxable: $0.taxable) }
        ) : nil
        return ComputedDocument(
            title: title(), chargesTax: chargesTax,
            placeOfSupply: config.regions.isEmpty ? nil : placeOfSupply,
            sameRegion: config.regions.isEmpty ? nil : sameRegion,
            reverseCharge: reverseCharge, inclusive: inclusive, lines: computedLines, shipping: computedShipping,
            taxLines: taxLines, totals: totals, home: home, notes: notes, issues: issues
        )
    }
}

private extension TaxCondition {
    /// A condition with no keys: always matches.
    static let always = TaxCondition(supplyType: nil, sameRegion: nil, sellerRegistration: nil, buyerIsBusiness: nil,
                                     buyerHasTaxId: nil, reverseCharge: nil, docType: nil, foreignCurrency: nil,
                                     totalAtLeastMinor: nil)
}
