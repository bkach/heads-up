import AppKit
import Foundation
import os

private let schedulerLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "HeadsUp",
    category: "scheduler"
)

@MainActor
final class ReminderScheduler {
    private let eventStore: EventStoreService
    private var reconcileTimer: Timer?
    private var alertTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var clockObserver: NSObjectProtocol?
    private var shownKeys: [String: Date] = [:]
    private var snoozedUntil: [String: Date] = [:]
    private let shownDefaultsKey = "shownOccurrences.v1"

    private(set) var settings = AppSettings.load()
    private(set) var events: [MeetingEvent] = []
    private(set) var health: ReminderHealth = .unknown
    private(set) var pausedUntil: Date?
    var onAlert: ((MeetingEvent) -> Void)?

    init(eventStore: EventStoreService) {
        self.eventStore = eventStore
        loadShownKeys()
        eventStore.onStoreChanged = { [weak self] in self?.scheduleReconcile(reason: "calendar changed") }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReconcile(reason: "Mac woke") }
        }
        clockObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReconcile(reason: "clock changed") }
        }
    }

    deinit {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let clockObserver { NotificationCenter.default.removeObserver(clockObserver) }
    }

    func start() async {
        reconcileTimer?.invalidate()
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: HeadsUpConfiguration.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reconcile(reason: "safety refresh") }
        }
        let granted = await eventStore.requestAccessIfNeeded()
        guard granted else {
            health = .permissionRequired
            postStateChanged()
            return
        }
        await reconcile(reason: "launch")
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        settings.save()
        Task { await reconcile(reason: "settings changed") }
    }

    func setPaused(for interval: TimeInterval?) {
        pausedUntil = interval.map { Date().addingTimeInterval($0) }
        armNextAlert()
        postStateChanged()
    }

    func snooze(_ event: MeetingEvent, for interval: TimeInterval = HeadsUpConfiguration.snoozeInterval) {
        snoozedUntil[event.occurrenceKey] = Date().addingTimeInterval(interval)
        shownKeys.removeValue(forKey: event.occurrenceKey)
        persistShownKeys()
        armNextAlert()
        postStateChanged()
    }

    func acknowledge(_ event: MeetingEvent) {
        shownKeys[event.occurrenceKey] = Date()
        snoozedUntil.removeValue(forKey: event.occurrenceKey)
        pruneAndPersistShownKeys()
        armNextAlert()
        postStateChanged()
    }

    func testAlert() {
        let now = Date()
        onAlert?(MeetingEvent(
            identifier: "test",
            title: "Heads Up test meeting",
            startDate: now.addingTimeInterval(42),
            endDate: now.addingTimeInterval(30 * 60),
            calendarIdentifier: "test",
            calendarTitle: "Test",
            joinURL: URL(string: "https://meet.google.com/test-meeting"),
            location: nil,
            notes: nil,
            isAllDay: false,
            isDeclined: false,
            isAcceptedOrOwned: true,
            hasAttendees: true
        ))
    }

    func requestPermissionAgain() {
        Task { await start() }
    }

    private func scheduleReconcile(reason: String) {
        Task { await reconcile(reason: reason) }
    }

    private func reconcile(reason: String) async {
        guard eventStore.authorizationStatus == .fullAccess else {
            health = .permissionRequired
            alertTimer?.invalidate()
            postStateChanged()
            return
        }

        health = .refreshing
        postStateChanged()
        do {
            events = try await eventStore.fetchUpcoming(settings: settings)
            let nextDate = nextEligibleAlertDate()
            health = .healthy(lastRefresh: Date(), nextAlert: nextDate)
            schedulerLog.info("Reconciled because \(reason, privacy: .public); events=\(self.events.count), next=\(nextDate?.description ?? "none", privacy: .public)")
            armNextAlert()
        } catch {
            health = .failed(error.localizedDescription)
            schedulerLog.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
        }
        postStateChanged()
    }

    private func nextEligibleAlertDate(now: Date = Date()) -> Date? {
        guard settings.alertsEnabled, pausedUntil.map({ $0 > now }) != true else { return nil }
        for event in events where shownKeys[event.occurrenceKey] == nil {
            if let snooze = snoozedUntil[event.occurrenceKey], snooze > now { return snooze }
            let target = event.startDate.addingTimeInterval(-settings.leadTime)
            if target > now { return target }
            if event.startDate.addingTimeInterval(-HeadsUpConfiguration.lateAlertGracePeriod) <= now && event.endDate > now { return now }
        }
        return nil
    }

    private func armNextAlert() {
        alertTimer?.invalidate()
        guard let target = nextEligibleAlertDate() else { return }
        alertTimer = Timer(fireAt: target, interval: 0, target: self, selector: #selector(alertTimerFired), userInfo: nil, repeats: false)
        RunLoop.main.add(alertTimer!, forMode: .common)
    }

    @objc private func alertTimerFired() {
        let now = Date()
        guard settings.alertsEnabled, pausedUntil.map({ $0 > now }) != true else {
            armNextAlert()
            return
        }
        guard let event = events.first(where: { candidate in
            guard shownKeys[candidate.occurrenceKey] == nil else { return false }
            if let snooze = snoozedUntil[candidate.occurrenceKey] { return snooze <= now }
            return candidate.startDate.addingTimeInterval(-settings.leadTime) <= now && candidate.endDate > now
        }) else {
            scheduleReconcile(reason: "timer had no matching event")
            return
        }

        // One takeover is enough for simultaneous events. Mark the whole start-time cluster so a
        // second zero-delay timer cannot replace an alert that is already on screen.
        for simultaneous in events where abs(simultaneous.startDate.timeIntervalSince(event.startDate)) < HeadsUpConfiguration.simultaneousEventThreshold {
            shownKeys[simultaneous.occurrenceKey] = now
        }
        snoozedUntil.removeValue(forKey: event.occurrenceKey)
        pruneAndPersistShownKeys()
        onAlert?(event)
        armNextAlert()
        postStateChanged()
    }

    private func loadShownKeys() {
        guard let data = UserDefaults.standard.data(forKey: shownDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        shownKeys = decoded
        pruneAndPersistShownKeys()
    }

    private func pruneAndPersistShownKeys() {
        let cutoff = Date().addingTimeInterval(-HeadsUpConfiguration.shownOccurrenceRetention)
        shownKeys = shownKeys.filter { $0.value > cutoff }
        persistShownKeys()
    }

    private func persistShownKeys() {
        guard let data = try? JSONEncoder().encode(shownKeys) else { return }
        UserDefaults.standard.set(data, forKey: shownDefaultsKey)
    }

    private func postStateChanged() {
        NotificationCenter.default.post(name: .headsUpStateChanged, object: self)
    }
}
