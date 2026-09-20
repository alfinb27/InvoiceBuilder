import Foundation

/// The arithmetic building blocks of the tax engine (`spec/tax/ENGINE.md` §2). Money never touches `Double`:
/// amounts are `Int64` minor units, intermediate values are `Decimal`.
public enum SpecMath {
    private static let half = Decimal(sign: .plus, exponent: -1, significand: 5)

    /// `round(x, mode)` to a whole number of minor units, by meaning (`ENGINE.md` §2.2). Implemented directly
    /// rather than through library rounding modes, whose names differ between platforms for negative values.
    public static func round(_ x: Decimal, _ mode: RoundingMode) -> Int64 {
        int64(roundedDecimal(x, mode))
    }

    static func roundedDecimal(_ x: Decimal, _ mode: RoundingMode) -> Decimal {
        let magnitude = x < 0 ? -x : x
        let whole = floor(magnitude)
        let fraction = magnitude - whole
        let rounded: Decimal = switch mode {
        case .towardZero: whole
        case .halfAwayFromZero: fraction >= half ? whole + 1 : whole
        case .halfEven:
            if fraction > half { whole + 1 } else if fraction < half { whole } else { isEven(whole) ? whole : whole + 1 }
        }
        return x < 0 ? -rounded : rounded
    }

    /// Largest integer ≤ `x`.
    static func floor(_ x: Decimal) -> Decimal {
        var value = x
        var result = Decimal()
        NSDecimalRound(&result, &value, 0, .down) // Foundation's .down rounds toward −∞
        return result
    }

    private static func isEven(_ whole: Decimal) -> Bool {
        floor(whole / 2) * 2 == whole
    }

    /// `distribute(total, exacts)` (`ENGINE.md` §2.3): whole parts of the exact shares, then one more to the items
    /// with the largest fractional parts (ties to the lower index), so the parts always add up to `total`.
    public static func distribute(_ total: Int64, _ exacts: [Decimal]) -> [Int64] {
        let floors = exacts.map(floor)
        var parts = floors.map(int64)
        let remainder = total - parts.reduce(0, +)
        let order = exacts.indices.sorted { lhs, rhs in
            let left = exacts[lhs] - floors[lhs], right = exacts[rhs] - floors[rhs]
            return left != right ? left > right : lhs < rhs
        }
        for index in order.prefix(Int(max(0, min(remainder, Int64(parts.count))))) {
            parts[index] += 1
        }
        return parts
    }

    /// `allocateProportional(total, weights)` (`ENGINE.md` §2.4); when every weight is 0 the first item gets it all.
    public static func allocateProportional(_ total: Int64, _ weights: [Int64]) -> [Int64] {
        guard !weights.isEmpty else { return [] }
        let sum = weights.reduce(0, +)
        guard sum != 0 else { return [total] + Array(repeating: 0, count: weights.count - 1) }
        let totalDecimal = Decimal(total), sumDecimal = Decimal(sum)
        return distribute(total, weights.map { totalDecimal * Decimal($0) / sumDecimal })
    }

    /// A whole-number `Decimal` as `Int64` (exact; values are always far inside the range).
    static func int64(_ whole: Decimal) -> Int64 {
        Int64(NSDecimalNumber(decimal: whole).stringValue) ?? 0
    }

    /// `10^exponent` as an exact `Decimal` (the exponent may be negative).
    static func powerOfTen(_ exponent: Int) -> Decimal {
        Decimal(sign: .plus, exponent: exponent, significand: 1)
    }
}
