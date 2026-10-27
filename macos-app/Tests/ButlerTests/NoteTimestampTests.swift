import AppKit
import Testing
@testable import Butler

@Suite struct NoteTimestampTests {
    // A fixed zone, so the tests don't depend on where they run.
    private var dublin: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return c
    }
    private func at(_ stamp: String) -> Date { NoteTimestamp.date(from: stamp)! }

    private func text(_ stamp: String, now: String, _ calendar: Calendar? = nil) -> String? {
        NoteTimestamp.parts(updatedAt: stamp, now: at(now), calendar: calendar ?? dublin).map { "\($0.day) \($0.time)" }
    }

    @Test func todayShowsTodayAndTheTime() {
        #expect(text("2026-10-28T16:35:00Z", now: "2026-10-28T20:00:00Z") == "Today 4:35 PM") // GMT on 28 Oct
        #expect(text("2026-10-28T00:05:00Z", now: "2026-10-28T20:00:00Z") == "Today 12:05 AM")
    }

    @Test func yesterdayShowsYesterday() {
        #expect(text("2026-10-27T22:00:00Z", now: "2026-10-28T08:00:00Z") == "Yesterday 10:00 PM")
    }

    @Test func theLastWeekShowsTheWeekday() {
        #expect(text("2026-10-26T10:00:00Z", now: "2026-10-28T10:00:00Z") == "Monday 10:00 AM")  // 2 days back
        #expect(text("2026-10-22T10:00:00Z", now: "2026-10-28T10:00:00Z") == "Thursday 11:00 AM") // 6 days back, still BST
    }

    @Test func withinAYearShowsTheDateWithoutYear() {
        #expect(text("2026-10-21T10:00:00Z", now: "2026-10-28T10:00:00Z") == "21 Oct 11:00 AM") // 7 days back
        #expect(text("2026-09-12T08:02:00Z", now: "2026-10-28T10:00:00Z") == "12 Sep 9:02 AM")
        #expect(text("2025-11-02T10:00:00Z", now: "2026-10-28T10:00:00Z") == "2 Nov 10:00 AM")  // last year, under a year ago
    }

    @Test func overAYearAgoShowsTheYear() {
        #expect(text("2025-10-27T10:00:00Z", now: "2026-10-28T10:00:00Z") == "27 Oct 2025 10:00 AM")
        #expect(text("2025-03-12T10:02:00Z", now: "2026-10-28T10:00:00Z") == "12 Mar 2025 10:02 AM")
    }

    // Days are counted in local time, not UTC: 23:30 UTC on the 27th is 00:30
    // on the 28th in Berlin, so it's today there.
    @Test func daysFollowTheLocalCalendar() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        #expect(text("2026-10-27T23:30:00Z", now: "2026-10-28T10:00:00Z", berlin) == "Today 12:30 AM")
        #expect(text("2026-10-27T23:30:00Z", now: "2026-10-28T10:00:00Z") == "Yesterday 11:30 PM") // Dublin: still the 27th
    }

    // A note from the future (clock was wrong when saved) shows its date.
    @Test func futureDateShowsTheDate() {
        #expect(text("2027-01-05T10:00:00Z", now: "2026-10-28T10:00:00Z") == "5 Jan 10:00 AM")
    }

    @Test func unreadableTimestampShowsNothing() {
        #expect(NoteTimestamp.parts(updatedAt: "") == nil)
        #expect(NoteTimestamp.parts(updatedAt: "yesterday-ish") == nil)
    }

    // The column must fit the widest real timestamp, so it never truncates.
    @Test func columnFitsTheWidestTimestamp() {
        let widest = [("28 May 2088", "12:59 PM"), ("Wednesday", "12:59 PM"), ("Yesterday", "10:00 AM")].map {
            NoteCellView.timestampText(day: $0.0, time: $0.1).size().width
        }.max()!
        #expect(NoteCellView.timestampColumnWidth >= widest)
    }

    // Right-aligned in its column, whatever the label's own setting.
    @Test func timestampIsRightAligned() {
        let text = NoteCellView.timestampText(day: "Today", time: "1:25 AM")
        let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .right)
    }

    // The row's text width leaves room for the timestamp column.
    @Test func rowTextWidthMakesRoomForTheTimestamp() {
        let width = NoteCellView.textWidth(forCellWidth: 640)
        #expect(width == 640 - NoteCellView.horizontalMargin - NoteCellView.timestampGap
                - NoteCellView.timestampColumnWidth - NoteCellView.timestampTrailingMargin)
    }
}
