import EventKit
import Foundation

@MainActor
final class EventStoreService {
    private let store = EKEventStore()
    private(set) var calendars: [EKCalendar] = []
    private var changeObserver: NSObjectProtocol?
    var onStoreChanged: (() -> Void)?

    init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onStoreChanged?() }
        }
    }

    deinit {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccessIfNeeded() async -> Bool {
        switch authorizationStatus {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) == true
        default:
            return false
        }
    }

    func fetchUpcoming(settings: AppSettings, now: Date = Date()) async throws -> [MeetingEvent] {
        calendars = store.calendars(for: .event).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        let selected = settings.selectedCalendarIDs.isEmpty
            ? calendars
            : calendars.filter { settings.selectedCalendarIDs.contains($0.calendarIdentifier) }
        let start = now.addingTimeInterval(-HeadsUpConfiguration.calendarLookback)
        let end = now.addingTimeInterval(HeadsUpConfiguration.calendarHorizon)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)

        let events = await Task.detached(priority: .userInitiated) { [store] in
            store.events(matching: predicate)
        }.value

        return events.compactMap { event in
            let currentUser = event.attendees?.first(where: \.isCurrentUser)
            let declined = currentUser?.participantStatus == .declined || event.status == .canceled
            let owned = event.organizer?.isCurrentUser == true
            // Personal events do not identify a current-user attendee. Invited events must be
            // explicitly accepted; organizer-owned events are always treated as accepted.
            let accepted = owned || currentUser == nil || currentUser?.participantStatus == .accepted
            let extractedURL = MeetingLinkExtractor.extract(
                url: event.url,
                location: event.location,
                notes: event.notes
            )
            let snapshot = MeetingEvent(
                identifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled event",
                startDate: event.startDate,
                endDate: event.endDate,
                calendarIdentifier: event.calendar.calendarIdentifier,
                calendarTitle: event.calendar.title,
                joinURL: extractedURL,
                location: event.location,
                notes: event.notes,
                isAllDay: event.isAllDay,
                isDeclined: declined,
                isAcceptedOrOwned: accepted,
                hasAttendees: !(event.attendees ?? []).isEmpty
            )
            return Self.isEligible(snapshot, settings: settings, now: now) ? snapshot : nil
        }
        .sorted { lhs, rhs in
            if lhs.startDate == rhs.startDate { return lhs.title < rhs.title }
            return lhs.startDate < rhs.startDate
        }
    }

    nonisolated static func isEligible(_ event: MeetingEvent, settings: AppSettings, now: Date) -> Bool {
        guard event.endDate > now, !event.isDeclined else { return false }
        if settings.ignoreAllDay && event.isAllDay { return false }
        if settings.acceptedOnly && !event.isAcceptedOrOwned { return false }
        if settings.videoOnly && event.joinURL == nil { return false }
        return true
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
