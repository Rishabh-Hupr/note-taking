import Foundation

// Wording for the periodic "📒 last note 3h ago" menu-bar hint. Pure and
// unit-tested; AppDelegate decides when to show it.
enum LastSavedHint {
    /// Menu choices for how often the hint appears (0 = off).
    static let choices: [(title: String, seconds: TimeInterval)] = [
        ("Off", 0),
        ("Every 30 minutes", 30 * 60),
        ("Every hour", 60 * 60),
        ("Every 2 hours", 2 * 60 * 60),
        ("Every 4 hours", 4 * 60 * 60),
    ]
    static let defaultInterval: TimeInterval = 2 * 60 * 60
    /// Longest interval accepted (from the menu store or the env var). Keeps the
    /// value finite and small enough to convert to nanoseconds without trapping.
    static let maxInterval: TimeInterval = 7 * 24 * 60 * 60
    static let defaultsKey = "butler.lastNoteHintInterval"

    /// The interval chosen in the menu (saved), 0 if turned off.
    /// BUTLER_HINT_INTERVAL=<seconds> overrides it to see the hint sooner while testing.
    static func interval(defaults: UserDefaults = .standard,
                         environment: [String: String] = ProcessInfo.processInfo.environment) -> TimeInterval {
        if let seconds = environmentOverride(environment) { return seconds }
        guard defaults.object(forKey: defaultsKey) != nil else { return defaultInterval }
        let saved = defaults.double(forKey: defaultsKey)
        guard saved.isFinite, saved >= 0 else { return defaultInterval }
        return min(saved, maxInterval)
    }

    /// BUTLER_HINT_INTERVAL in seconds, if set (testing aid; beats the menu choice).
    static func environmentOverride(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> TimeInterval? {
        guard let raw = environment["BUTLER_HINT_INTERVAL"], let seconds = TimeInterval(raw),
              seconds.isFinite, seconds > 0 else { return nil }
        return min(seconds, maxInterval)
    }

    static func setInterval(_ seconds: TimeInterval, defaults: UserDefaults = .standard) {
        defaults.set(seconds, forKey: defaultsKey)
    }

    /// How long the hint stays before shrinking back.
    static let visibleFor: TimeInterval = 20

    /// "last note 3h ago" for a note's `updated_at`, or "no notes yet".
    static func text(newestUpdatedAt: String?, now: Date = Date()) -> String {
        guard let stamp = newestUpdatedAt, let saved = NoteTimestamp.date(from: stamp) else {
            return "no notes yet"
        }
        return "last note \(relative(from: saved, to: now))"
    }

    /// Compact age: just now · 25m ago · 3h ago · 2d ago.
    static func relative(from earlier: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(earlier))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }
}
