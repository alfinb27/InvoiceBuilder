package app.invoicebuilder.core.domain.support

import java.time.LocalDate
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

/** Where timestamps and calendar dates come from, so tests and previews can fix them. iOS: `TimeSource`. */
class TimeSource(
    /** Epoch milliseconds, UTC (audit timestamps). */
    val now: () -> Long,
    /** Today's calendar date on this device (invoice dates, rates in force). */
    val today: () -> LocalDate,
) {
    companion object {
        val system = TimeSource({ System.currentTimeMillis() }, { LocalDate.now() })
        fun fixed(now: Long, today: LocalDate) = TimeSource({ now }, { today })
    }
}

/** Makes new record ids: lowercase UUID strings (`CLAUDE.md` rule 3). iOS: `IDGenerator`. */
class IDGenerator(val make: () -> String) {
    companion object {
        /** `java.util.UUID.toString()` is already lowercase. */
        val random = IDGenerator { UUID.randomUUID().toString() }

        /** Predictable ids for tests: `00000000-0000-4000-8000-000000000001`, `…002`, … */
        fun sequential(first: Int = 1): IDGenerator {
            val counter = AtomicInteger(first)
            return IDGenerator { "00000000-0000-4000-8000-" + counter.getAndIncrement().toString(16).padStart(12, '0') }
        }
    }
}
