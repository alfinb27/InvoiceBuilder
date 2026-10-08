package app.invoicebuilder.core.domain.dates

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.SerializationException
import java.time.LocalDate

/**
 * Calendar dates are `java.time.LocalDate` (≈ iOS's own `LocalDate`): `YYYY-MM-DD`, no time zone.
 * [parseIsoDate] is strict, like the Swift `LocalDate(iso:)`.
 */
private val isoDate = Regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")

fun parseIsoDate(text: String): LocalDate? {
    if (!isoDate.matches(text)) return null
    val year = text.substring(0, 4).toInt()
    if (year < 1) return null
    return runCatching { LocalDate.of(year, text.substring(5, 7).toInt(), text.substring(8, 10).toInt()) }.getOrNull()
}

/** `YYYY-MM-DD`. */
val LocalDate.iso: String get() = "%04d-%02d-%02d".format(year, monthValue, dayOfMonth)

/** Days since 1970-01-01 (Swift: `daysSinceEpoch`). */
val LocalDate.daysSinceEpoch: Long get() = toEpochDay()

/** `LocalDate` as its ISO string in JSON (≈ Swift's `Codable` conformance). */
object LocalDateSerializer : KSerializer<LocalDate> {
    override val descriptor = PrimitiveSerialDescriptor("LocalDate", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: LocalDate) = encoder.encodeString(value.iso)
    override fun deserialize(decoder: Decoder): LocalDate {
        val text = decoder.decodeString()
        return parseIsoDate(text) ?: throw SerializationException("Not a YYYY-MM-DD date: $text")
    }
}

typealias IsoDate = @Serializable(with = LocalDateSerializer::class) LocalDate

/** A month and day without a year (`MM-DD`), e.g. a fiscal year start (`04-01` in India, `04-06` in the UK). */
@Serializable(with = MonthDaySerializer::class)
data class MonthDay(val month: Int, val day: Int) : Comparable<MonthDay> {
    override fun compareTo(other: MonthDay): Int = compareValuesBy(this, other, MonthDay::month, MonthDay::day)
    override fun toString(): String = "%02d-%02d".format(month, day)

    companion object {
        fun of(month: Int, day: Int): MonthDay? =
            if (month in 1..12 && day in 1..LocalDate.of(2000, month, 1).lengthOfMonth()) MonthDay(month, day) else null

        /** Strict `MM-DD`. */
        fun parse(text: String): MonthDay? {
            val parts = text.split("-")
            if (parts.size != 2 || parts[0].length != 2 || parts[1].length != 2) return null
            return of(parts[0].toIntOrNull() ?: return null, parts[1].toIntOrNull() ?: return null)
        }
    }
}

object MonthDaySerializer : KSerializer<MonthDay> {
    override val descriptor = PrimitiveSerialDescriptor("MonthDay", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: MonthDay) = encoder.encodeString(value.toString())
    override fun deserialize(decoder: Decoder): MonthDay {
        val text = decoder.decodeString()
        return MonthDay.parse(text) ?: throw SerializationException("Not an MM-DD value: $text")
    }
}
