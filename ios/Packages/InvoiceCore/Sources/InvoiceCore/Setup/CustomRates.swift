/// Business-defined tax rates for GENERIC countries (`spec/setup.md` §7).
public enum CustomRates {
    /// Every GENERIC business has it, so items always have a valid rate even if the business registers later.
    public static let noTax = TaxRate(
        id: "none", category: .zero, label: "No tax", effectiveFrom: LocalDate(year: 2000, month: 1, day: 1)!,
        components: [RateComponent(code: "TAX", label: "Tax", percent: "0")]
    )

    /// The rates onboarding creates: the named rate (tax-charging registrations only), then "No tax".
    public static func initialRates(chargesTax: Bool, taxName: String, percent: String, today: LocalDate,
                                    newID: () -> String) -> [TaxRate] {
        guard chargesTax else { return [noTax] }
        let draft = CustomRateDraft(name: taxName, percent: percent)
        return [draft.makeRate(id: rateID(fromUUID: newID()), today: today), noTax]
    }

    /// `r` + the first 8 hex digits of a UUID (a valid config id: `^[A-Za-z][A-Za-z0-9_]*$`); `r` + all 32 hex
    /// digits when a rate in `existing` already has the short id (`spec/setup.md` §7).
    public static func rateID(fromUUID uuid: String, existing: [TaxRate] = []) -> String {
        let hex = uuid.lowercased().filter(\.isHexDigit)
        let short = "r" + String(hex.prefix(8))
        return existing.contains { $0.id == short } ? "r" + hex : short
    }

    /// `T` upper-cased, keeping only `A–Z 0–9`, at most 12 characters; `TAX` when nothing is left.
    public static func componentCode(forName name: String) -> String {
        let code = String(name.uppercased().unicodeScalars.filter { scalar in
            ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
        }.prefix(12).map(Character.init))
        return code.isEmpty ? "TAX" : code
    }

    /// A typed percent that is not a decimal in 0–100.
    public static func percentIssue(_ text: String) -> FieldIssue? {
        switch DecimalInput.parse(text) {
        case .failure(let error):
            return error == .empty ? .required : .invalidNumber(error)
        case .success(let value):
            guard let decimal = DecimalString.parse(value), decimal <= 100 else { return .outOfRange(0...100) }
            return nil
        }
    }
}

public enum CustomRateField: Hashable, Sendable {
    case name, percent, secondName, secondPercent
}

/// A custom rate being edited: one component, or two with the second optionally compound.
public struct CustomRateDraft: Equatable, Sendable {
    public var name: String
    public var percent: String
    public var hasSecondComponent = false
    public var secondName = ""
    public var secondPercent = ""
    public var secondIsCompound = false

    public init(name: String = "", percent: String = "") {
        self.name = name
        self.percent = percent
    }

    public init(rate: TaxRate) {
        let components = rate.components ?? []
        name = components.first?.label ?? rate.label
        percent = components.first?.percent ?? rate.percent ?? ""
        if components.count > 1 {
            hasSecondComponent = true
            secondName = components[1].label
            secondPercent = components[1].percent
            secondIsCompound = components[1].compound ?? false
        }
    }

    public var issues: [CustomRateField: FieldIssue] {
        var issues: [CustomRateField: FieldIssue] = [:]
        if name.trimmedOrNil == nil { issues[.name] = .required }
        if let issue = CustomRates.percentIssue(percent) { issues[.percent] = issue }
        if hasSecondComponent {
            if secondName.trimmedOrNil == nil { issues[.secondName] = .required }
            if let issue = CustomRates.percentIssue(secondPercent) { issues[.secondPercent] = issue }
        }
        return issues
    }

    /// The stored rate; label `"T p%"`, or `"T1 p1% + T2 p2%"` (`+ " (compound)"`).
    public func makeRate(id: String, today: LocalDate) -> TaxRate {
        var components = [component(name: name, percent: percent, compound: nil)]
        if hasSecondComponent {
            components.append(component(name: secondName, percent: secondPercent, compound: secondIsCompound ? true : nil))
        }
        let label = components.map { "\($0.label) \($0.percent)%" }.joined(separator: " + ")
            + (secondIsCompound && hasSecondComponent ? " (compound)" : "")
        return TaxRate(id: id, category: .standard, label: label, effectiveFrom: today, components: components)
    }

    private func component(name: String, percent: String, compound: Bool?) -> RateComponent {
        let label = name.trimmedOrNil ?? "Tax"
        let value = (try? DecimalInput.parse(percent).get()) ?? "0"
        return RateComponent(code: CustomRates.componentCode(forName: label), label: label, percent: value,
                             compound: compound)
    }
}
