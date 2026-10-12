package app.invoicebuilder.core.domain.tax

import app.invoicebuilder.core.domain.dates.iso
import app.invoicebuilder.core.domain.decimal.DecimalString
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.support.trimmedOrNull
import java.math.BigDecimal

/**
 * `TaxEngine.compute(input) → ComputedDocument` (`spec/tax/ENGINE.md` §3): a pure function (no clock, locale or
 * I/O) that interprets a country's tax config. Each step below is one numbered step of the spec. Ported from
 * `InvoiceCore/Tax/TaxEngine.swift`; the `tax` fixtures prove both.
 */
object TaxEngine {
    /** @throws TaxEngineError when the input cannot be computed (`ENGINE.md` §3 "Errors vs issues"). */
    fun compute(input: EngineInput): ComputedDocument {
        val computation = Computation(input)
        computation.run()
        return computation.output()
    }
}

/** A line or shipping pseudo-line on its way through the steps ("tax unit"). */
private class TaxUnit(
    val amount: Long,
    var discount: Long = 0,
    var net: Long,
    val rate: TaxRate,
    val isShipping: Boolean,
    val productCode: String? = null,
) {
    var components: List<TaxComponent> = emptyList()
    var totalPercent: BigDecimal = BigDecimal.ZERO
    var taxes: MutableList<Long> = mutableListOf()
    var taxable: Long = 0
}

private data class TaxComponent(
    /** Null for a non-tax group (exempt, nil-rated, outside scope). */
    val code: String?,
    val percent: BigDecimal,
    val category: TaxCategory,
    val compound: Boolean,
) {
    val key: TaxLineKey get() = TaxLineKey(code, DecimalString.string(percent), category)
}

private data class TaxLineKey(val code: String?, val rate: String, val category: TaxCategory)

private class Computation(val input: EngineInput) {
    companion object {
        val nonTaxCategories = setOf(TaxCategory.exempt, TaxCategory.nilRated, TaxCategory.outsideScope)
        val hundred: BigDecimal = BigDecimal(100)
    }

    val config get() = input.config
    val draft get() = input.draft
    val seller get() = input.seller
    val buyer get() = input.buyer

    // Step 0: context
    val registration: TaxRegistration = config.registration(seller.registration)
        ?: throw TaxEngineError(TaxEngineError.Code.InvalidInput)
    val chargesTax = registration.chargesTax
    val effectiveDate = draft.supplyDate ?: draft.issueDate
    val sellerRegion: String? = run {
        val region = seller.region?.trimmedOrNull
        val length = config.taxIDFormat?.regionFromPrefix
        val taxID = seller.taxId?.trimmedOrNull
        when {
            region != null -> region
            length != null && taxID != null && taxID.length >= length -> taxID.substring(0, length)
            else -> null
        }
    }
    val placeOfSupply: String? = run {
        val country = buyer.country?.trimmedOrNull
        when {
            config.regions.isEmpty() -> null
            draft.placeOfSupply?.trimmedOrNull != null -> draft.placeOfSupply!!.trimmedOrNull
            // an explicit foreign country only; no country means domestic
            country != null && country != config.country -> config.foreignRegion
            else -> buyer.region?.trimmedOrNull ?: sellerRegion
        }
    }
    val sameRegion = placeOfSupply != null && placeOfSupply == sellerRegion
    val foreignCurrency = draft.currency != seller.homeCurrency
    val reverseCharge = draft.reverseCharge && config.reverseCharge.supported && chargesTax
    val inclusive = draft.pricesIncludeTax && chargesTax && !reverseCharge
    val buyerHasTaxID = buyer.taxId?.trimmedOrNull != null

    // Step 1
    var rule: ComponentRule? = null

    val lines = mutableListOf<TaxUnit>()
    var shipping = mutableListOf<TaxUnit>()
    val staleRateLines = mutableListOf<Int>()
    var subtotal = 0L
    var discountTotal = 0L
    var shippingTotal = 0L
    val taxLines = mutableListOf<ComputedTaxLine>()
    var totals = ComputedTotals(0, 0, 0, 0, 0, 0, 0, 0)
    var home: HomeTotals? = null
    val notes = mutableListOf<ComputedNote>()
    val issues = mutableListOf<EngineIssue>()

    /** Invoice-level results waiting to be aggregated in Step 7: (key, taxable, tax). */
    var invoiceTaxLines: List<Triple<TaxLineKey, Long, Long>> = emptyList()

    fun run() {
        selectRule()
        computeLineAmounts()
        allocateInvoiceDiscount()
        splitShipping()
        assignComponents()
        computeTaxes()
        collectTaxLines()
        computeTotals()
        collectNotes()
        runChecks()
    }

    private fun div(numerator: BigDecimal, divisor: BigDecimal): BigDecimal = numerator.divide(divisor, SpecMath.context)

    // MARK: Step 1: component rule

    fun selectRule() {
        if (!chargesTax) return
        rule = config.componentRules.firstOrNull { matches(it.condition, null) }
            ?: throw TaxEngineError(TaxEngineError.Code.NoComponentRule)
    }

    /** Every key the condition lists must match; list keys match when the value is in the list. */
    fun matches(condition: TaxCondition, total: Long?): Boolean {
        condition.supplyType?.let { if (draft.supplyType !in it) return false }
        condition.sameRegion?.let { if (it != sameRegion) return false }
        condition.sellerRegistration?.let { if (seller.registration !in it) return false }
        condition.buyerIsBusiness?.let { if (it != buyer.isBusiness) return false }
        condition.buyerHasTaxId?.let { if (it != buyerHasTaxID) return false }
        condition.reverseCharge?.let { if (it != reverseCharge) return false }
        condition.docType?.let { if (draft.docType.rawValue !in it) return false }
        condition.foreignCurrency?.let { if (it != foreignCurrency) return false }
        condition.totalAtLeastMinor?.let { minimum -> if (total == null || total < minimum) return false }
        return true
    }

    // MARK: Step 2: line amounts

    fun computeLineAmounts() {
        val rates = config.availableRates(seller.customRates)
        for ((index, line) in draft.lines.withIndex()) {
            val quantity = DecimalString.parse(line.quantity)
            if (quantity == null || quantity.signum() < 0 || line.unitPrice < 0) {
                throw TaxEngineError(TaxEngineError.Code.InvalidInput, index)
            }
            val gross = quantity * BigDecimal.valueOf(line.unitPrice)
            val lineDiscount = when (val discount = line.discount) {
                is Discount.Percent -> {
                    val percent = DecimalString.parse(discount.value)
                    if (percent == null || percent.signum() < 0) throw TaxEngineError(TaxEngineError.Code.InvalidInput, index)
                    div(gross * percent, hundred)
                }
                is Discount.Amount -> {
                    if (discount.value < 0) throw TaxEngineError(TaxEngineError.Code.InvalidInput, index)
                    BigDecimal.valueOf(discount.value)
                }
                null -> BigDecimal.ZERO
            }
            if (lineDiscount > gross) throw TaxEngineError(TaxEngineError.Code.LineDiscountExceedsAmount, index)
            val rate = rates.firstOrNull { it.id == line.rateId } ?: throw TaxEngineError(TaxEngineError.Code.UnknownRate, index)
            if (!rate.isInForce(effectiveDate)) staleRateLines += index
            val amount = SpecMath.round(gross - lineDiscount, config.rounding.amountMode)
            lines += TaxUnit(amount = amount, net = amount, rate = rate, isShipping = false, productCode = line.productCode)
        }
        subtotal = lines.sumOf { it.amount }
    }

    // MARK: Step 3: invoice discount

    fun allocateInvoiceDiscount() {
        discountTotal = when (val discount = draft.discount) {
            is Discount.Percent -> {
                val percent = DecimalString.parse(discount.value)
                if (percent == null || percent.signum() < 0) throw TaxEngineError(TaxEngineError.Code.InvalidInput)
                SpecMath.round(div(BigDecimal.valueOf(subtotal) * percent, hundred), config.rounding.amountMode)
            }
            is Discount.Amount -> {
                if (discount.value < 0) throw TaxEngineError(TaxEngineError.Code.InvalidInput)
                discount.value
            }
            null -> 0
        }
        if (discountTotal > subtotal) throw TaxEngineError(TaxEngineError.Code.DiscountExceedsSubtotal)
        val shares = SpecMath.allocateProportional(discountTotal, lines.map { it.amount })
        for ((index, line) in lines.withIndex()) {
            line.discount = shares[index]
            line.net = line.amount - shares[index]
        }
    }

    // MARK: Step 4: shipping

    fun splitShipping() {
        shippingTotal = draft.shipping ?: 0
        if (shippingTotal < 0) throw TaxEngineError(TaxEngineError.Code.InvalidInput)
        if (shippingTotal == 0L) return
        if (lines.isEmpty()) throw TaxEngineError(TaxEngineError.Code.InvalidInput) // shipping takes its rate from the lines
        when (config.shipping.rule) {
            ShippingRule.principalSupplyRate -> {
                // The line with the largest net amount; ties go to the lowest index.
                var principal = 0
                for (index in lines.indices) if (lines[index].net > lines[principal].net) principal = index
                shipping = mutableListOf(TaxUnit(amount = shippingTotal, net = shippingTotal, rate = lines[principal].rate, isShipping = true))
            }
            ShippingRule.apportion -> {
                val groups = mutableListOf<Pair<TaxRate, Long>>()
                for (line in lines) {
                    val index = groups.indexOfFirst { it.first.id == line.rate.id }
                    if (index >= 0) groups[index] = groups[index].first to groups[index].second + line.net
                    else groups += line.rate to line.net
                }
                val parts = SpecMath.allocateProportional(shippingTotal, groups.map { it.second })
                shipping = groups.zip(parts).mapNotNull { (group, part) ->
                    if (part > 0) TaxUnit(amount = part, net = part, rate = group.first, isShipping = true) else null
                }.toMutableList()
            }
        }
    }

    // MARK: Step 5: components per line

    fun assignComponents() {
        val rule = rule
        if (!chargesTax || rule == null) return
        for ((index, line) in lines.withIndex()) {
            line.components = components(line.rate, rule, index)
            line.totalPercent = line.components.fold(BigDecimal.ZERO) { sum, it -> sum + it.percent }
        }
        for (unit in shipping) {
            unit.components = components(unit.rate, rule, null)
            unit.totalPercent = unit.components.fold(BigDecimal.ZERO) { sum, it -> sum + it.percent }
        }
    }

    fun components(rate: TaxRate, rule: ComponentRule, line: Int?): List<TaxComponent> {
        val components = mutableListOf<TaxComponent>()
        when (val source = rule.components) {
            ComponentSource.FromRate -> for (component in rate.components ?: emptyList()) {
                val percent = DecimalString.parse(component.percent) ?: throw TaxEngineError(TaxEngineError.Code.InvalidInput, line)
                components += TaxComponent(component.code, percent, rate.category, component.compound ?: false)
            }
            is ComponentSource.Listed -> for (reference in source.references) {
                var code = reference.code
                if (code == "\$localComponent") {
                    val local = placeOfSupply?.let { config.region(it)?.localComponent }
                        ?: throw TaxEngineError(TaxEngineError.Code.UnknownRegion, line)
                    code = local
                }
                val percent = if (reference.rateOverride != null) {
                    DecimalString.parse(reference.rateOverride) ?: throw TaxEngineError(TaxEngineError.Code.InvalidInput, line)
                } else {
                    val ratePercent = rate.percent?.let(DecimalString::parse)
                    val share = DecimalString.parse(reference.share)
                    if (ratePercent == null || share == null) throw TaxEngineError(TaxEngineError.Code.InvalidInput, line)
                    ratePercent * share
                }
                components += TaxComponent(code, percent, reference.categoryOverride ?: rate.category, false)
            }
        }
        // Exempt, nil-rated and outside-scope supplies carry no tax: one non-tax group instead of components.
        components.firstOrNull { it.category in nonTaxCategories }?.let { nonTax ->
            return listOf(TaxComponent(null, BigDecimal.ZERO, nonTax.category, false))
        }
        if (inclusive && components.any { it.compound }) {
            throw TaxEngineError(TaxEngineError.Code.InclusiveCompoundUnsupported, line)
        }
        return components
    }

    // MARK: Step 6: taxable value and tax

    fun computeTaxes() {
        if (!chargesTax) {
            for (unit in lines + shipping) unit.taxable = unit.net
            return
        }
        when (config.rounding.taxLevel) {
            TaxLevel.line -> for (unit in lines + shipping) taxLine(unit)
            TaxLevel.invoice -> if (inclusive) taxInvoiceInclusive() else taxInvoiceExclusive()
        }
    }

    /** Line level: each line (and shipping pseudo-line) is rounded on its own. */
    fun taxLine(unit: TaxUnit) {
        val mode = config.rounding.taxMode
        unit.taxes = mutableListOf()
        if (inclusive) {
            val divisor = hundred + unit.totalPercent
            for (component in unit.components) {
                unit.taxes += SpecMath.round(div(BigDecimal.valueOf(unit.net) * component.percent, divisor), mode)
            }
            unit.taxable = unit.net - unit.taxes.sum()
        } else {
            unit.taxable = unit.net
            var accumulated = 0L
            for (component in unit.components) {
                val base = BigDecimal.valueOf(unit.taxable) + (if (component.compound) BigDecimal.valueOf(accumulated) else BigDecimal.ZERO)
                val tax = SpecMath.round(div(base * component.percent, hundred), mode)
                unit.taxes += tax
                accumulated += tax
            }
        }
    }

    private data class ExclusiveGroup(val key: TaxLineKey, val component: TaxComponent, var taxable: Long)

    /** Invoice level, exclusive prices: exact tax per group, rounded once per component code across the invoice. */
    fun taxInvoiceExclusive() {
        for (unit in lines + shipping) unit.taxable = unit.net
        val groups = mutableListOf<ExclusiveGroup>()
        for (unit in lines + shipping) {
            for (component in unit.components) {
                val existing = groups.firstOrNull { it.key == component.key }
                if (existing != null) existing.taxable += unit.taxable else groups += ExclusiveGroup(component.key, component, unit.taxable)
            }
        }
        val exacts = groups.map { div(BigDecimal.valueOf(it.taxable) * it.component.percent, hundred) }
        val taxes = MutableList(groups.size) { 0L }
        for (code in orderedCodes(groups.map { it.component.code })) {
            val members = groups.indices.filter { groups[it].component.code == code }
            val total = SpecMath.round(members.fold(BigDecimal.ZERO) { sum, it -> sum + exacts[it] }, config.rounding.taxMode)
            for ((member, part) in members.zip(SpecMath.distribute(total, members.map { exacts[it] }))) taxes[member] = part
        }
        invoiceTaxLines = groups.zip(taxes).map { (group, tax) ->
            Triple(group.key, group.taxable, if (group.component.code == null) 0L else tax)
        }
    }

    private class InclusiveGroup(
        val keys: List<TaxLineKey>,
        val components: List<TaxComponent>,
        val totalPercent: BigDecimal,
        val members: MutableList<Pair<Boolean, Int>>,
    ) {
        var inclusiveTotal = 0L
        var exacts: List<BigDecimal> = emptyList()
        var taxes: MutableList<Long> = mutableListOf()
    }

    private fun unit(member: Pair<Boolean, Int>): TaxUnit = if (member.first) shipping[member.second] else lines[member.second]

    /** Invoice level, inclusive prices: lines grouped by identical component set; the typed totals are kept exactly. */
    fun taxInvoiceInclusive() {
        val groups = mutableListOf<InclusiveGroup>()
        val units = lines.indices.map { false to it } + shipping.indices.map { true to it }
        for (member in units) {
            val unit = unit(member)
            val keys = unit.components.map { it.key }
            val existing = groups.firstOrNull { it.keys == keys }
            if (existing != null) existing.members += member
            else groups += InclusiveGroup(keys, unit.components, unit.totalPercent, mutableListOf(member))
        }
        for (group in groups) {
            val total = group.members.sumOf { unit(it).net }
            group.inclusiveTotal = total
            val divisor = hundred + group.totalPercent
            group.exacts = group.components.map { div(BigDecimal.valueOf(total) * it.percent, divisor) }
            group.taxes = MutableList(group.components.size) { 0L }
        }
        val codes = orderedCodes(groups.flatMap { group -> group.components.map { it.code } })
        for (code in codes) {
            val members = mutableListOf<Pair<Int, Int>>()
            for ((groupIndex, group) in groups.withIndex()) {
                for ((componentIndex, component) in group.components.withIndex()) {
                    if (component.code == code) members += groupIndex to componentIndex
                }
            }
            val exacts = members.map { groups[it.first].exacts[it.second] }
            val total = SpecMath.round(exacts.fold(BigDecimal.ZERO) { sum, it -> sum + it }, config.rounding.taxMode)
            for ((member, part) in members.zip(SpecMath.distribute(total, exacts))) {
                groups[member.first].taxes[member.second] = part
            }
        }
        val taxLines = mutableListOf<Triple<TaxLineKey, Long, Long>>()
        for (group in groups) {
            val groupTax = group.taxes.sum()
            // For display, the group's tax is split across its lines in proportion to their net amounts.
            val divisor = hundred + group.totalPercent
            val shares = if (group.totalPercent.signum() == 0) {
                List(group.members.size) { 0L }
            } else {
                SpecMath.distribute(groupTax, group.members.map { div(BigDecimal.valueOf(unit(it).net) * group.totalPercent, divisor) })
            }
            for ((member, share) in group.members.zip(shares)) unit(member).taxable = unit(member).net - share
            val groupTaxable = group.inclusiveTotal - groupTax
            for ((key, tax) in group.keys.zip(group.taxes)) taxLines += Triple(key, groupTaxable, if (key.code == null) 0L else tax)
        }
        invoiceTaxLines = taxLines
    }

    /** Component codes in order of first appearance. */
    fun orderedCodes(codes: List<String?>): List<String?> {
        val seen = mutableListOf<String?>()
        for (code in codes) if (code !in seen) seen += code
        return seen
    }

    // MARK: Step 7: tax lines

    fun collectTaxLines() {
        if (!chargesTax) return
        val entries: List<Triple<TaxLineKey, Long, Long>> = when (config.rounding.taxLevel) {
            TaxLevel.line -> (lines + shipping).flatMap { unit ->
                unit.components.zip(unit.taxes).map { (component, tax) ->
                    Triple(component.key, unit.taxable, if (component.code == null) 0L else tax)
                }
            }
            TaxLevel.invoice -> invoiceTaxLines
        }
        val charged = !reverseCharge
        for ((key, taxable, tax) in entries) {
            val index = taxLines.indexOfFirst { it.component == key.code && it.rate == key.rate && it.category == key.category }
            if (index >= 0) {
                taxLines[index] = taxLines[index].copy(taxable = taxLines[index].taxable + taxable, tax = taxLines[index].tax + tax)
            } else {
                taxLines += ComputedTaxLine(key.code, key.rate, key.category, taxable, tax, charged, null)
            }
        }
    }

    // MARK: Steps 8–9: totals and home currency

    fun computeTotals() {
        val taxable = (lines + shipping).sumOf { it.taxable }
        val tax = taxLines.filter { it.charged }.sumOf { it.tax }
        val taxNotCharged = taxLines.filter { !it.charged }.sumOf { it.tax }
        var roundOff = 0L
        val grandTotal = config.rounding.grandTotal
        if (grandTotal != null && (draft.roundOff ?: grandTotal.defaultOn) && grandTotal.roundToMinor > 0) {
            val beforeRounding = taxable + tax
            val rounded = SpecMath.round(div(BigDecimal.valueOf(beforeRounding), BigDecimal.valueOf(grandTotal.roundToMinor)), grandTotal.mode) *
                grandTotal.roundToMinor
            roundOff = rounded - beforeRounding
        }
        totals = ComputedTotals(subtotal, discountTotal, shippingTotal, taxable, tax, taxNotCharged, roundOff, taxable + tax + roundOff)

        val rateText = draft.exchangeRate?.trimmedOrNull
        if (!foreignCurrency || !config.foreignCurrency.homeTotals || rateText == null) return
        val rate = DecimalString.parse(rateText)
        if (rate == null || rate.signum() <= 0) throw TaxEngineError(TaxEngineError.Code.InvalidInput)
        val scale = SpecMath.powerOfTen(input.currencies.exponent(seller.homeCurrency) - input.currencies.exponent(draft.currency))
        val mode = config.rounding.amountMode
        val convert = { amount: Long -> SpecMath.round(BigDecimal.valueOf(amount) * rate * scale, mode) }
        home = HomeTotals(seller.homeCurrency, rateText, convert(taxable), convert(tax), convert(totals.total))
        if (config.foreignCurrency.taxInHomeCurrency) {
            for (index in taxLines.indices) taxLines[index] = taxLines[index].copy(homeTax = convert(taxLines[index].tax))
        }
    }

    // MARK: Step 10: notes

    fun collectNotes() {
        val ids = (registration.notes ?: emptyList()).toMutableList()
        if (chargesTax) ids += rule?.notes ?: emptyList()
        if (reverseCharge) ids += config.reverseCharge.notes ?: emptyList()
        val seen = mutableSetOf<String>()
        for (id in ids) {
            if (!seen.add(id)) continue
            config.notesCatalog[id]?.let { notes += ComputedNote(id, it.text, it.placement) }
        }
    }

    // MARK: Step 12: checks → issues

    fun runChecks() {
        if (staleRateLines.isNotEmpty()) issues += EngineIssue("rate_not_effective", EngineIssue.Severity.warning, staleRateLines.toList())
        val comparedTotal = if (foreignCurrency) home?.total else totals.total
        for (check in config.checks) {
            if (!matches(check.condition ?: TaxCondition.always, comparedTotal)) continue
            val severity = EngineIssue.Severity(check.severity)
            when (check.type ?: "require") {
                "require" -> if ((check.require ?: emptyList()).any { field(it)?.trimmedOrNull == null }) {
                    issues += EngineIssue(check.code, severity)
                }
                "productCodeDigits" -> {
                    val tiers = config.productCodes?.tiers ?: continue
                    val first = tiers.firstOrNull() ?: continue
                    val tier = seller.turnoverMinor?.let { turnover ->
                        tiers.firstOrNull { tier -> tier.maxTurnoverMinor?.let { it >= turnover } ?: true } ?: tiers.last()
                    } ?: first
                    val required = if (buyerHasTaxID) tier.b2bDigits else tier.b2cDigits
                    if (required <= 0) continue
                    val short = lines.indices.filter { digitCount(lines[it].productCode) < required }
                    if (short.isNotEmpty()) issues += EngineIssue(check.code, severity, short)
                }
                else -> continue
            }
        }
    }

    fun field(path: String): String? = when (path) {
        "seller.taxId" -> seller.taxId
        "seller.lutReference" -> seller.lutReference
        "seller.address" -> seller.address
        "buyer.name" -> buyer.name
        "buyer.address" -> buyer.address
        "buyer.region" -> buyer.region
        "buyer.taxId" -> buyer.taxId
        "buyer.country" -> buyer.country
        "draft.exchangeRate" -> draft.exchangeRate
        "draft.dueDate" -> draft.dueDate?.iso
        else -> null
    }

    fun digitCount(code: String?): Int = (code ?: "").count { it in '0'..'9' }

    // MARK: Step 11 and output

    fun title(): String {
        if (draft.docType == DocumentType.quote) return registration.titles.quote
        val allExempt = registration.titles.invoiceAllExempt
        if (allExempt != null && chargesTax && lines.all { line ->
                line.components.size == 1 && line.components[0].code == null &&
                    line.components[0].category in listOf(TaxCategory.exempt, TaxCategory.nilRated)
            }
        ) return allExempt
        return registration.titles.invoice
    }

    fun output(): ComputedDocument {
        val lineTaxes = chargesTax && config.rounding.taxLevel == TaxLevel.line
        val computedLines = lines.map { line ->
            ComputedLine(
                amount = line.amount, discount = line.discount, taxable = line.taxable, rateId = line.rate.id,
                rate = if (chargesTax) DecimalString.string(line.totalPercent) else "0",
                category = if (chargesTax) line.components.firstOrNull()?.category ?: line.rate.category else line.rate.category,
                taxes = if (lineTaxes) line.components.zip(line.taxes).map { (component, tax) ->
                    LineTax(component.code, DecimalString.string(component.percent), if (component.code == null) 0 else tax)
                } else null,
            )
        }
        val computedShipping = if (shippingTotal > 0) ComputedShipping(
            amount = shippingTotal, taxable = shipping.sumOf { it.taxable },
            parts = shipping.map { ShippingPart(it.rate.id, it.amount, it.taxable) },
        ) else null
        return ComputedDocument(
            title = title(), chargesTax = chargesTax,
            placeOfSupply = if (config.regions.isEmpty()) null else placeOfSupply,
            sameRegion = if (config.regions.isEmpty()) null else sameRegion,
            reverseCharge = reverseCharge, inclusive = inclusive, lines = computedLines, shipping = computedShipping,
            taxLines = taxLines.toList(), totals = totals, home = home, notes = notes.toList(), issues = issues.toList(),
        )
    }
}
