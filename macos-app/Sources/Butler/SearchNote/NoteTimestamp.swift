import Foundation

// The "when" shown at the right end of a search row, from a note's updated_at:
// a day, with the time under it (NoteCellView draws the time smaller).
//   Today / 5:35 PM · Yesterday / 9:12 PM · Monday / 1:32 PM · 12 Sep / 9:02 AM
//   and the year only once a note is over a year old: 12 Mar 2025 / 10:02 AM
// Pure and unit-tested.
enum NoteTimestamp {
    private static let parser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime] // the backend's RFC3339, e.g. 2026-10-17T09:00:00Z
        return f
    }()

    /// A backend timestamp ("2026-10-17T09:00:00Z") as a date, nil if malformed.
    static func date(from stamp: String) -> Date? { parser.date(from: stamp) }

    /// The day and time for `updatedAt` in `calendar`'s time zone (local by
    /// default), or nil if the timestamp can't be read.
    static func parts(updatedAt: String, now: Date = Date(),
                      calendar: Calendar = .current) -> (day: String, time: String)? {
        guard let saved = date(from: updatedAt) else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: saved),
                                           to: calendar.startOfDay(for: now)).day ?? Int.max
        let day: String
        switch days {
        case 0: day = "Today"
        case 1: day = "Yesterday"
        case 2...6: day = formatter("EEEE", calendar).string(from: saved)
        default:
            // Older (or from the future, if the clock was wrong): the date, with
            // the year only once the note is more than a year old.
            let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            day = formatter(saved < yearAgo ? "d MMM yyyy" : "d MMM", calendar).string(from: saved)
        }
        return (day, formatter("h:mm a", calendar).string(from: saved))
    }

    // Formatters are costly to create and every visible row needs one, so
    // they're kept per format and time zone. Locked: safe from any thread.
    private static var formatters: [String: DateFormatter] = [:]
    private static let formattersLock = NSLock()

    // Fixed English format ("Sep", "PM") whatever the system language, as asked.
    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let cacheKey = "\(format)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        formattersLock.lock(); defer { formattersLock.unlock() }
        if let cached = formatters[cacheKey] { return cached }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        formatters[cacheKey] = f
        return f
    }
}
