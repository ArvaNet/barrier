import Foundation

/// A calendar date with no time or time zone ("2026-10-09"). All schedule math
/// runs on these, so daylight-saving shifts can never move a night.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible, Identifiable {
    public var id: Int { ordinal }
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(parts[0], parts[1], parts[2])
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    // MARK: Ordinal days (Howard Hinnant's civil calendar algorithms)

    /// Days since 1970-01-01.
    public var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public init(ordinal: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(y + (m <= 2 ? 1 : 0), m, d)
    }

    public func adding(_ days: Int) -> Day { Day(ordinal: ordinal + days) }

    /// Whole days from self to other (other − self).
    public func days(to other: Day) -> Int { other.ordinal - ordinal }

    /// 0 = Sunday … 6 = Saturday.
    public var weekday: Int { ((ordinal % 7) + 7 + 4) % 7 }

    public var firstOfMonth: Day { Day(year, month, 1) }

    public var daysInMonth: Int {
        let next = month == 12 ? Day(year + 1, 1, 1) : Day(year, month + 1, 1)
        return firstOfMonth.days(to: next)
    }

    public func addingMonths(_ n: Int) -> Day {
        var m = month - 1 + n
        var y = year
        y += Int((Double(m) / 12).rounded(.down))
        m = ((m % 12) + 12) % 12
        let first = Day(y, m + 1, 1)
        return Day(y, m + 1, min(day, first.daysInMonth))
    }

    public static func < (a: Day, b: Day) -> Bool { a.ordinal < b.ordinal }

    // MARK: Codable as "YYYY-MM-DD"

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let d = Day(iso: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad day \(s)")
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}

/// Before this hour, it still counts as "last night" (a 1 a.m. routine belongs to the evening before).
public let dayRolloverHour = 4

public extension Day {
    /// The calendar day of a moment in the given calendar's time zone.
    static func of(_ date: Date, calendar: Calendar = .barrier) -> Day {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return Day(c.year!, c.month!, c.day!)
    }

    /// The routine day a moment belongs to.
    static func routineDay(_ date: Date = Date(), calendar: Calendar = .barrier) -> Day {
        let hour = calendar.component(.hour, from: date)
        let d = Day.of(date, calendar: calendar)
        return hour < dayRolloverHour ? d.adding(-1) : d
    }

    /// Local midnight of this day.
    func date(calendar: Calendar = .barrier) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}

/// A wall-clock time ("21:30").
public struct ClockTime: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var hour: Int
    public var minute: Int

    public init(_ hour: Int, _ minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    public init?(string: String) {
        let p = string.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        self.init(p[0], p[1])
    }

    public var string: String { String(format: "%02d:%02d", hour, minute) }
    public var description: String { string }
    public var minutes: Int { hour * 60 + minute }

    public static func < (a: ClockTime, b: ClockTime) -> Bool { a.minutes < b.minutes }

    public func adding(minutes n: Int) -> ClockTime {
        let t = ((minutes + n) % 1440 + 1440) % 1440
        return ClockTime(t / 60, t % 60)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let t = ClockTime(string: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad time \(s)")
        }
        self = t
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}

/// A moment on a routine day. Times before the rollover hour fall on the next calendar day.
public struct DayTime: Hashable, Sendable {
    public var day: Day
    public var time: ClockTime

    public init(_ day: Day, _ time: ClockTime) {
        self.day = day
        self.time = time
    }

    /// The calendar date the clock shows when this fires.
    public var calendarDay: Day { time.hour < dayRolloverHour ? day.adding(1) : day }

    public var components: DateComponents {
        let d = calendarDay
        return DateComponents(year: d.year, month: d.month, day: d.day, hour: time.hour, minute: time.minute)
    }

    public func date(calendar: Calendar = .barrier) -> Date {
        calendar.date(from: components) ?? Date.distantPast
    }

    public func adding(minutes: Int, calendar: Calendar = .barrier) -> Date {
        date(calendar: calendar).addingTimeInterval(TimeInterval(minutes * 60))
    }
}

public extension Calendar {
    /// Gregorian in the current time zone. All day math uses this, whatever
    /// calendar the iPhone displays (Buddhist, Hebrew, Islamic…), so weekdays
    /// and dates always line up with `Day`.
    static var barrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        c.locale = Locale.current
        return c
    }
}
