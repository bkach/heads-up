import Foundation

@main
enum LogicTests {
    static func main() {
        var failures: [String] = []
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { failures.append(message) }
        }

        let meet = MeetingLinkExtractor.extract(
            url: nil,
            location: "Room 4",
            notes: "Agenda https://example.com/doc and join https://meet.google.com/abc-defg-hij"
        )
        expect(meet?.host == "meet.google.com", "prefers known meeting URL over an earlier generic URL")

        let zoom = MeetingLinkExtractor.extract(
            url: URL(string: "https://zoom.us/j/123456"),
            location: nil,
            notes: nil
        )
        expect(zoom?.absoluteString == "https://zoom.us/j/123456", "extracts structured Zoom URL")

        let unsafe = MeetingLinkExtractor.extract(
            url: URL(string: "javascript:alert(1)"),
            location: nil,
            notes: nil
        )
        expect(unsafe == nil, "rejects non-web URL schemes")

        let generic = MeetingLinkExtractor.extract(
            url: nil,
            location: nil,
            notes: "Agenda https://example.com/document"
        )
        expect(generic == nil, "does not treat a generic event link as a meeting URL")

        let now = Date()
        let base = MeetingEvent(
            identifier: "event-1",
            title: "Test",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(1800),
            calendarIdentifier: "work",
            calendarTitle: "Work",
            joinURL: nil,
            location: nil,
            notes: nil,
            isAllDay: false,
            isDeclined: false,
            isAcceptedOrOwned: true,
            hasAttendees: true
        )
        expect(EventStoreService.isEligible(base, settings: AppSettings(), now: now), "accepts normal upcoming event")

        var videoOnly = AppSettings()
        videoOnly.videoOnly = true
        expect(!EventStoreService.isEligible(base, settings: videoOnly, now: now), "video-only excludes events without links")

        let key1 = base.occurrenceKey
        let moved = MeetingEvent(
            identifier: base.identifier,
            title: base.title,
            startDate: base.startDate.addingTimeInterval(300),
            endDate: base.endDate.addingTimeInterval(300),
            calendarIdentifier: base.calendarIdentifier,
            calendarTitle: base.calendarTitle,
            joinURL: base.joinURL,
            location: base.location,
            notes: base.notes,
            isAllDay: base.isAllDay,
            isDeclined: base.isDeclined,
            isAcceptedOrOwned: base.isAcceptedOrOwned,
            hasAttendees: base.hasAttendees
        )
        expect(key1 != moved.occurrenceKey, "moving an event creates a new alert occurrence")

        let sameOccurrenceWithDifferentIdentifier = MeetingEvent(
            identifier: "different-id",
            title: base.title,
            startDate: base.startDate,
            endDate: base.endDate,
            calendarIdentifier: "secondary",
            calendarTitle: "Secondary",
            joinURL: base.joinURL,
            location: base.location,
            notes: base.notes,
            isAllDay: base.isAllDay,
            isDeclined: base.isDeclined,
            isAcceptedOrOwned: base.isAcceptedOrOwned,
            hasAttendees: base.hasAttendees
        )
        expect(key1 == sameOccurrenceWithDifferentIdentifier.occurrenceKey, "identifies the same occurrence across calendar copies")

        if failures.isEmpty {
            print("✅ Logic tests passed")
        } else {
            failures.forEach { print("❌ \($0)") }
            exit(1)
        }
    }
}
