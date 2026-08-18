import Foundation

enum HeadsUpConfiguration {
    static let refreshInterval: TimeInterval = 30
    static let calendarLookback: TimeInterval = 10 * 60
    static let calendarHorizon: TimeInterval = 48 * 60 * 60
    static let lateAlertGracePeriod: TimeInterval = 5 * 60
    static let shownOccurrenceRetention: TimeInterval = 48 * 60 * 60
    static let simultaneousEventThreshold: TimeInterval = 30
    static let defaultLeadTime: TimeInterval = 60
    static let leadTimeOptions: [TimeInterval] = [0, 60, 120, 300]
    static let snoozeInterval: TimeInterval = 60
    static let pauseInterval: TimeInterval = 60 * 60
    static let alertSoundName = "Glass"
}

struct MeetingEvent: Codable, Hashable, Sendable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let calendarIdentifier: String
    let calendarTitle: String
    let joinURL: URL?
    let location: String?
    let notes: String?
    let isAllDay: Bool
    let isDeclined: Bool
    let isAcceptedOrOwned: Bool
    let hasAttendees: Bool

    var occurrenceKey: String {
        let normalizedTitle = title
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(Int(startDate.timeIntervalSince1970))|\(normalizedTitle)"
    }

    var isHappening: Bool {
        let now = Date()
        return startDate <= now && endDate > now
    }
}

struct AppSettings: Codable, Equatable {
    var alertsEnabled = true
    var leadTime = HeadsUpConfiguration.defaultLeadTime
    var acceptedOnly = true
    var ignoreAllDay = true
    var videoOnly = false
    var showOnEveryDisplay = true
    var playSound = true
    var selectedCalendarIDs: Set<String> = []

    static let defaultsKey = "appSettings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

enum ReminderHealth: Equatable {
    case unknown
    case permissionRequired
    case refreshing
    case healthy(lastRefresh: Date, nextAlert: Date?)
    case failed(String)
}

extension Notification.Name {
    static let headsUpStateChanged = Notification.Name("HeadsUpStateChanged")
}
