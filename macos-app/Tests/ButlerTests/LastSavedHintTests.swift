import Foundation
import Testing
@testable import Butler

@Suite struct LastSavedHintTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00Z")!

    @Test(arguments: [
        ("2026-10-17T11:59:30Z", "last note just now"),
        ("2026-10-17T11:35:00Z", "last note 25m ago"),
        ("2026-10-17T09:00:00Z", "last note 3h ago"),
        ("2026-10-15T08:00:00Z", "last note 2d ago"),
    ])
    func wording(stamp: String, expected: String) {
        #expect(LastSavedHint.text(newestUpdatedAt: stamp, now: now) == expected)
    }

    @Test func noNotes() {
        #expect(LastSavedHint.text(newestUpdatedAt: nil, now: now) == "no notes yet")
        #expect(LastSavedHint.text(newestUpdatedAt: "not a date", now: now) == "no notes yet")
    }

    @Test func futureTimestampIsJustNow() {
        // Clock skew shouldn't produce negative ages.
        #expect(LastSavedHint.text(newestUpdatedAt: "2026-10-17T12:05:00Z", now: now) == "last note just now")
    }
}

@Suite struct LastSavedHintIntervalTests {
    private func freshDefaults() -> UserDefaults {
        let name = "butler-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func defaultsToTwoHours() {
        #expect(LastSavedHint.interval(defaults: freshDefaults(), environment: [:]) == 2 * 60 * 60)
    }

    @Test func savedChoiceIsUsed() {
        let d = freshDefaults()
        LastSavedHint.setInterval(30 * 60, defaults: d)
        #expect(LastSavedHint.interval(defaults: d, environment: [:]) == 30 * 60)
    }

    @Test func offIsZero() {
        let d = freshDefaults()
        LastSavedHint.setInterval(0, defaults: d)
        #expect(LastSavedHint.interval(defaults: d, environment: [:]) == 0)
    }

    @Test func environmentOverrideWins() {
        let d = freshDefaults()
        LastSavedHint.setInterval(0, defaults: d)
        #expect(LastSavedHint.interval(defaults: d, environment: ["BUTLER_HINT_INTERVAL": "30"]) == 30)
    }

    @Test func environmentOverrideIsReportedSeparately() {
        #expect(LastSavedHint.environmentOverride(["BUTLER_HINT_INTERVAL": "45"]) == 45)
        #expect(LastSavedHint.environmentOverride([:]) == nil)
        #expect(LastSavedHint.environmentOverride(["BUTLER_HINT_INTERVAL": "nope"]) == nil)
    }

    @Test func absurdIntervalsAreRejectedOrClamped() {
        // Huge / infinite values would trap when converted to nanoseconds.
        #expect(LastSavedHint.environmentOverride(["BUTLER_HINT_INTERVAL": "inf"]) == nil)
        #expect(LastSavedHint.environmentOverride(["BUTLER_HINT_INTERVAL": "1e12"]) == LastSavedHint.maxInterval)
        let d = freshDefaults()
        d.set(Double.infinity, forKey: LastSavedHint.defaultsKey)
        #expect(LastSavedHint.interval(defaults: d, environment: [:]) == LastSavedHint.defaultInterval)
        d.set(1e12, forKey: LastSavedHint.defaultsKey)
        #expect(LastSavedHint.interval(defaults: d, environment: [:]) == LastSavedHint.maxInterval)
    }

    @Test func menuOffersOffAndTheDefault() {
        let seconds = LastSavedHint.choices.map(\.seconds)
        #expect(seconds.contains(0))
        #expect(seconds.contains(LastSavedHint.defaultInterval))
    }
}
