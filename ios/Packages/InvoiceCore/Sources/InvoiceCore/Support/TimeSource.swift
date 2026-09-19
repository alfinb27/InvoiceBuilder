import Foundation
import Synchronization

/// Where timestamps and calendar dates come from, so tests and previews can fix them.
public struct TimeSource: Sendable {
    /// Epoch milliseconds, UTC (audit timestamps).
    public var now: @Sendable () -> Int64
    /// Today's calendar date on this device (invoice dates, rates in force).
    public var today: @Sendable () -> LocalDate

    public init(now: @escaping @Sendable () -> Int64, today: @escaping @Sendable () -> LocalDate) {
        self.now = now
        self.today = today
    }

    public static let system = TimeSource(
        now: { Int64((Date().timeIntervalSince1970 * 1000).rounded()) },
        today: { LocalDate.today() }
    )

    public static func fixed(now: Int64, today: LocalDate) -> TimeSource {
        TimeSource(now: { now }, today: { today })
    }
}

/// Makes new record ids: lowercase UUID strings (`CLAUDE.md` rule 3).
public struct IDGenerator: Sendable {
    public var make: @Sendable () -> String

    public init(make: @escaping @Sendable () -> String) {
        self.make = make
    }

    /// `UUID().uuidString` is upper-case; ids are always stored lower-case.
    public static let random = IDGenerator { UUID().uuidString.lowercased() }

    /// Predictable ids for tests: `00000000-0000-4000-8000-000000000001`, `…002`, …
    public static func sequential(startingAt first: Int = 1) -> IDGenerator {
        let counter = Mutex(first)
        return IDGenerator {
            let n = counter.withLock { value in
                defer { value += 1 }
                return value
            }
            let suffix = String(n, radix: 16)
            return "00000000-0000-4000-8000-" + String(repeating: "0", count: max(0, 12 - suffix.count)) + suffix
        }
    }
}
