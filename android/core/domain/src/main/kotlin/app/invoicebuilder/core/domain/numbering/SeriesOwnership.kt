package app.invoicebuilder.core.domain.numbering

import app.invoicebuilder.core.domain.decimal.Outcome
import app.invoicebuilder.core.domain.documents.DocumentLifecycle
import app.invoicebuilder.core.domain.models.DocumentType
import app.invoicebuilder.core.domain.models.NumberingSeries
import app.invoicebuilder.core.domain.tax.TaxConfig

/**
 * Numbering on several devices (`spec/sync.md` §3). Android has no sync in v1, but a restored backup can bring in
 * another device's series, and the rules are the same. iOS: `SeriesOwnership`.
 */
object SeriesOwnership {
    enum class Failure(val rawValue: String) { NoDeviceLetter("no_device_letter") }

    data class DevicePattern(val pattern: String, val label: String)

    /** §3.1: the pattern and label for a new series on this device. */
    fun deviceSeriesPattern(defaultPattern: String, docType: DocumentType, existingPatterns: List<String>): Outcome<DevicePattern, Failure> {
        val taken = existingPatterns.mapNotNull(::letterBeforeSequence).toSet()
        val letter = ('B'..'Z').firstOrNull { it !in taken }
        val token = defaultPattern.indexOf("{seq")
        if (letter == null || token < 0) return Outcome.Failure(Failure.NoDeviceLetter)
        val pattern = defaultPattern.substring(0, token) + letter + defaultPattern.substring(token)
        return Outcome.Success(DevicePattern(pattern, "${baseLabel(docType)} ($letter)"))
    }

    /** §3.1: the new series itself. */
    fun deviceSeries(
        id: String, businessID: String, docType: DocumentType, config: TaxConfig, existing: List<NumberingSeries>,
        deviceID: String, now: Long,
    ): Outcome<NumberingSeries, Failure> {
        val defaultPattern = if (docType == DocumentType.quote) config.numbering.quotePattern else config.numbering.invoicePattern
        val live = existing.filter { it.deletedAt == null && it.businessId == businessID && it.docType == docType }
        return when (val result = deviceSeriesPattern(defaultPattern, docType, live.map { it.pattern })) {
            is Outcome.Failure -> result
            is Outcome.Success -> Outcome.Success(
                NumberingSeries(
                    id = id, createdAt = now, updatedAt = now, businessId = businessID, docType = docType,
                    label = result.value.label, pattern = result.value.pattern, reset = config.numbering.reset,
                    ownerDeviceId = deviceID, counters = emptyMap(),
                ),
            )
        }
    }

    /** §3.2: counters after a takeover, given the highest issued sequence per period. */
    fun takeOverCounters(counters: Map<String, Int>, highest: Map<String, Int>): Map<String, Int> {
        val result = counters.toMutableMap()
        for ((period, sequence) in highest) result[period] = maxOf(counters[period] ?: 1, sequence + 1)
        return result
    }

    /** §3.2: the series owned by this device, continuing after every number already issued from it. */
    fun takeOver(series: NumberingSeries, deviceID: String, highest: Map<String, Int>, now: Long): NumberingSeries =
        series.copy(ownerDeviceId = deviceID, counters = takeOverCounters(series.counters, highest), updatedAt = now)

    /** The character right before the `{seq` token when it is an uppercase letter B–Z (the original counts as A). */
    fun letterBeforeSequence(pattern: String): Char? {
        val token = pattern.indexOf("{seq")
        if (token <= 0) return null
        val before = pattern[token - 1]
        return if (before in 'B'..'Z') before else null
    }

    fun baseLabel(docType: DocumentType): String = if (docType == DocumentType.quote) "Quotes" else "Invoices"
}

/** `spec/sync.md` §4: issued or void documents that share a number. iOS: `DuplicateNumbers`. */
object DuplicateNumbers {
    data class Row(val id: String, val docType: DocumentType, val lifecycle: DocumentLifecycle, val number: String?)

    data class Group(val docType: DocumentType, val number: String, /** Sorted. */ val ids: List<String>)

    /** Groups of two or more, by number then type; ids sorted. */
    fun find(rows: List<Row>): List<Group> = rows
        .filter { it.lifecycle != DocumentLifecycle.draft && it.number != null }
        .groupBy { it.docType to it.number!! }
        .filterValues { it.size > 1 }
        .map { (key, group) -> Group(key.first, key.second, group.map { it.id }.sorted()) }
        .sortedWith(compareBy<Group>({ it.number }, { it.docType.rawValue }))
}
