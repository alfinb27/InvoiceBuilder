package app.invoicebuilder.core.domain.tax

import java.math.BigDecimal
import java.math.RoundingMode as JavaRounding

/** The spec's rounding modes (`ENGINE.md` §2.2), by meaning. iOS: `RoundingMode`. */
@kotlinx.serialization.Serializable
enum class RoundingMode {
    halfAwayFromZero, halfEven, towardZero;

    companion object {
        fun of(rawValue: String): RoundingMode? = entries.firstOrNull { it.name == rawValue }
    }
}

/**
 * The arithmetic building blocks of the tax engine (`spec/tax/ENGINE.md` §2). Money never touches `Double`:
 * amounts are `Long` minor units, intermediate values are `BigDecimal`. iOS: `SpecMath`.
 */
object SpecMath {
    /** Division precision for intermediate values (more than Swift's `Decimal`, so results only round once). */
    val context = java.math.MathContext(50, JavaRounding.HALF_EVEN)

    /**
     * `round(x, mode)` to a whole number of minor units (`ENGINE.md` §2.2). Mapped by meaning: Java's `HALF_UP`
     * rounds half away from zero for negatives too, `DOWN` is toward zero.
     */
    fun round(x: BigDecimal, mode: RoundingMode): Long = roundedDecimal(x, mode).longValueExact()

    fun roundedDecimal(x: BigDecimal, mode: RoundingMode): BigDecimal = x.setScale(
        0,
        when (mode) {
            RoundingMode.halfAwayFromZero -> JavaRounding.HALF_UP
            RoundingMode.halfEven -> JavaRounding.HALF_EVEN
            RoundingMode.towardZero -> JavaRounding.DOWN
        },
    )

    /** Largest integer ≤ [x]. */
    fun floor(x: BigDecimal): BigDecimal = x.setScale(0, JavaRounding.FLOOR)

    /**
     * `distribute(total, exacts)` (`ENGINE.md` §2.3): whole parts of the exact shares, then one more to the items
     * with the largest fractional parts (ties to the lower index), so the parts always add up to [total].
     */
    fun distribute(total: Long, exacts: List<BigDecimal>): List<Long> {
        val floors = exacts.map(::floor)
        val parts = floors.map { it.longValueExact() }.toMutableList()
        val remainder = total - parts.sum()
        val order = exacts.indices.sortedWith { lhs, rhs ->
            val left = exacts[lhs] - floors[lhs]
            val right = exacts[rhs] - floors[rhs]
            if (left.compareTo(right) != 0) right.compareTo(left) else lhs.compareTo(rhs)
        }
        val extra = maxOf(0L, minOf(remainder, parts.size.toLong())).toInt()
        for (index in order.take(extra)) parts[index] += 1
        return parts
    }

    /** `allocateProportional(total, weights)` (`ENGINE.md` §2.4); when every weight is 0 the first item gets it all. */
    fun allocateProportional(total: Long, weights: List<Long>): List<Long> {
        if (weights.isEmpty()) return emptyList()
        val sum = weights.sum()
        if (sum == 0L) return listOf(total) + List(weights.size - 1) { 0L }
        val totalDecimal = BigDecimal.valueOf(total)
        val sumDecimal = BigDecimal.valueOf(sum)
        return distribute(total, weights.map { (totalDecimal * BigDecimal.valueOf(it)).divide(sumDecimal, context) })
    }

    /** `10^exponent` as an exact `BigDecimal` (the exponent may be negative). */
    fun powerOfTen(exponent: Int): BigDecimal = BigDecimal.ONE.scaleByPowerOfTen(exponent)
}
