import AppKit
import EventKit
import ServiceManagement

enum HeadsUpStyle {
    static let accent = NSColor(srgbRed: 139/255, green: 92/255, blue: 246/255, alpha: 1)
}

private final class GlassView: NSVisualEffectView {
    override var isFlipped: Bool { true }
}

private final class CardView: NSView {
    var highlighted = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        if highlighted {
            layer?.backgroundColor = HeadsUpStyle.accent.withAlphaComponent(dark ? 0.18 : 0.10).cgColor
            layer?.borderColor = HeadsUpStyle.accent.withAlphaComponent(dark ? 0.62 : 0.45).cgColor
        } else {
            layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.045)).cgColor
            layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06)).cgColor
        }
    }
}

@MainActor
final class PopoverController: NSViewController {
    private let scheduler: ReminderScheduler
    private let eventStore: EventStoreService
    private let width: CGFloat = 320
    private var stateObserver: NSObjectProtocol?
    private var root: GlassView!
    private var statusCard: CardView!
    private var statusTitle: NSTextField!
    private var statusDetail: NSTextField!
    private var alertsSwitch: NSSwitch!
    private var leadControl: NSSegmentedControl!
    private var acceptedSwitch: NSSwitch!
    private var videoSwitch: NSSwitch!
    private var allDisplaysSwitch: NSSwitch!
    private var calendarsButton: NSButton!
    private var soundSwitch: NSSwitch!
    private var loginSwitch: NSSwitch!
    private var pauseButton: NSButton!
    private var permissionButton: NSButton!

    init(scheduler: ReminderScheduler, eventStore: EventStoreService) {
        self.scheduler = scheduler
        self.eventStore = eventStore
        super.init(nibName: nil, bundle: nil)
        stateObserver = NotificationCenter.default.addObserver(
            forName: .headsUpStateChanged,
            object: scheduler,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
    }

    override func loadView() {
        root = GlassView(frame: NSRect(x: 0, y: 0, width: width, height: 690))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .followsWindowActiveState
        view = root
        buildUI()
        refresh()
    }

    private func buildUI() {
        let pad: CGFloat = 16
        let cardWidth = width - pad * 2
        let mark = NSImageView(frame: NSRect(x: pad, y: 14, width: 18, height: 18))
        mark.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Heads Up")
        mark.contentTintColor = HeadsUpStyle.accent
        root.addSubview(mark)
        addLabel("Heads Up", x: pad + 24, y: 14, width: 180, height: 20, size: 14, weight: .semibold)

        var y: CGFloat = 48
        y = addSection("NEXT", at: y)
        statusCard = card(x: pad, y: y, width: cardWidth, height: 74, highlighted: true)
        statusTitle = addLabel("Checking calendar…", in: statusCard, x: 12, y: 12, width: cardWidth - 24, height: 22, size: 14, weight: .semibold)
        statusDetail = addLabel("", in: statusCard, x: 12, y: 38, width: cardWidth - 24, height: 16, size: 11, color: .secondaryLabelColor)
        permissionButton = NSButton(title: "Allow Calendar Access", target: self, action: #selector(requestPermission))
        permissionButton.bezelStyle = .rounded
        permissionButton.frame = NSRect(x: 12, y: 42, width: 154, height: 25)
        permissionButton.isHidden = true
        statusCard.addSubview(permissionButton)
        y += 88

        y = addSection("ALERTS", at: y)
        let alertCard = card(x: pad, y: y, width: cardWidth, height: 104)
        alertsSwitch = addSwitch("Meeting alerts", detail: "Blocks the screen when it is time to join.", y: 12, in: alertCard, action: #selector(alertsToggled))
        addLabel("Alert me", in: alertCard, x: 12, y: 68, width: 96, height: 22, size: 12)
        leadControl = NSSegmentedControl(labels: ["At start", "1m", "2m", "5m"], trackingMode: .selectOne, target: self, action: #selector(leadChanged))
        leadControl.frame = NSRect(x: 101, y: 66, width: cardWidth - 113, height: 26)
        alertCard.addSubview(leadControl)
        y += 118

        y = addSection("WHEN TO ALERT", at: y)
        let filtersCard = card(x: pad, y: y, width: cardWidth, height: 148)
        addLabel("Calendars", in: filtersCard, x: 12, y: 12, width: 120, height: 22, size: 12)
        calendarsButton = NSButton(title: "All calendars", target: self, action: #selector(showCalendarsMenu))
        calendarsButton.bezelStyle = .rounded
        calendarsButton.frame = NSRect(x: cardWidth - 120, y: 10, width: 108, height: 25)
        filtersCard.addSubview(calendarsButton)
        acceptedSwitch = addSwitch("Accepted events only", y: 46, in: filtersCard, action: #selector(acceptedToggled))
        videoSwitch = addSwitch("Video meetings only", y: 80, in: filtersCard, action: #selector(videoToggled))
        allDisplaysSwitch = addSwitch("Show on every display", y: 114, in: filtersCard, action: #selector(displaysToggled))
        y += 162

        y = addSection("RELIABILITY", at: y)
        let reliabilityCard = card(x: pad, y: y, width: cardWidth, height: 120)
        soundSwitch = addSwitch("Play alert sound", y: 12, in: reliabilityCard, action: #selector(soundToggled))
        loginSwitch = addSwitch("Launch at login", y: 46, in: reliabilityCard, action: #selector(loginToggled))
        let test = NSButton(title: "Test full-screen alert", target: self, action: #selector(testAlert))
        test.bezelStyle = .rounded
        test.frame = NSRect(x: 12, y: 81, width: 154, height: 27)
        reliabilityCard.addSubview(test)
        pauseButton = NSButton(title: "Pause 1h", target: self, action: #selector(togglePause))
        pauseButton.bezelStyle = .rounded
        pauseButton.frame = NSRect(x: cardWidth - 102, y: 81, width: 90, height: 27)
        reliabilityCard.addSubview(pauseButton)
        y += 134

        let quit = NSButton(title: "Quit Heads Up", target: self, action: #selector(quit))
        quit.bezelStyle = .rounded
        quit.sizeToFit()
        quit.frame.origin = NSPoint(x: width - pad - quit.frame.width, y: y)
        root.addSubview(quit)
        y += quit.frame.height + pad
        root.frame.size.height = y
        preferredContentSize = NSSize(width: width, height: y)
    }

    private func refresh() {
        guard isViewLoaded else { return }
        let settings = scheduler.settings
        alertsSwitch.state = settings.alertsEnabled ? .on : .off
        leadControl.selectedSegment = HeadsUpConfiguration.leadTimeOptions.firstIndex(of: settings.leadTime) ?? 1
        acceptedSwitch.state = settings.acceptedOnly ? .on : .off
        videoSwitch.state = settings.videoOnly ? .on : .off
        allDisplaysSwitch.state = settings.showOnEveryDisplay ? .on : .off
        let count = settings.selectedCalendarIDs.count
        calendarsButton.title = count == 0 ? "All calendars" : "\(count) selected"
        soundSwitch.state = settings.playSound ? .on : .off
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        pauseButton.title = scheduler.pausedUntil.map { $0 > Date() } == true ? "Resume" : "Pause 1h"

        permissionButton.isHidden = true
        if let next = scheduler.events.first {
            statusTitle.stringValue = next.title
            let relative = RelativeDateTimeFormatter().localizedString(for: next.startDate, relativeTo: Date())
            let service = next.joinURL?.host.map { " · \($0)" } ?? ""
            statusDetail.stringValue = "\(relative)\(service) · alert \(formatTime(next.startDate.addingTimeInterval(-settings.leadTime)))"
        } else {
            switch scheduler.health {
            case .permissionRequired:
                statusTitle.stringValue = "Calendar access needed"
                statusDetail.stringValue = ""
                permissionButton.isHidden = false
            case .refreshing:
                statusTitle.stringValue = "Checking calendar…"
                statusDetail.stringValue = "Refreshing upcoming events."
            case .failed(let message):
                statusTitle.stringValue = "Calendar refresh failed"
                statusDetail.stringValue = message
            default:
                statusTitle.stringValue = "No upcoming meetings"
                statusDetail.stringValue = healthDescription()
            }
        }

    }

    private func healthDescription() -> String {
        switch scheduler.health {
        case .healthy(let lastRefresh, _): return "Calendar refreshed \(RelativeDateTimeFormatter().localizedString(for: lastRefresh, relativeTo: Date()))."
        case .unknown: return "Starting reminder engine."
        default: return "No eligible events in the next \(Int(HeadsUpConfiguration.calendarHorizon / 3600)) hours."
        }
    }

    @objc private func alertsToggled(_ sender: NSSwitch) { scheduler.updateSettings { $0.alertsEnabled = sender.state == .on } }
    @objc private func leadChanged(_ sender: NSSegmentedControl) {
        scheduler.updateSettings {
            $0.leadTime = HeadsUpConfiguration.leadTimeOptions[max(0, sender.selectedSegment)]
        }
    }
    @objc private func acceptedToggled(_ sender: NSSwitch) { scheduler.updateSettings { $0.acceptedOnly = sender.state == .on } }
    @objc private func videoToggled(_ sender: NSSwitch) { scheduler.updateSettings { $0.videoOnly = sender.state == .on } }
    @objc private func displaysToggled(_ sender: NSSwitch) { scheduler.updateSettings { $0.showOnEveryDisplay = sender.state == .on } }
    @objc private func showCalendarsMenu(_ sender: NSButton) {
        let menu = NSMenu()
        let all = NSMenuItem(title: "All calendars", action: #selector(toggleCalendar(_:)), keyEquivalent: "")
        all.target = self
        all.state = scheduler.settings.selectedCalendarIDs.isEmpty ? .on : .off
        all.representedObject = "__all__"
        menu.addItem(all)
        menu.addItem(.separator())
        for calendar in eventStore.calendars {
            let item = NSMenuItem(title: calendar.title, action: #selector(toggleCalendar(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = calendar.calendarIdentifier
            item.state = scheduler.settings.selectedCalendarIDs.isEmpty || scheduler.settings.selectedCalendarIDs.contains(calendar.calendarIdentifier) ? .on : .off
            menu.addItem(item)
        }
        let point = NSPoint(x: calendarsButton.bounds.maxX, y: calendarsButton.bounds.maxY)
        menu.popUp(positioning: nil, at: point, in: calendarsButton)
    }
    @objc private func toggleCalendar(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        scheduler.updateSettings { settings in
            if identifier == "__all__" {
                settings.selectedCalendarIDs.removeAll()
            } else {
                if settings.selectedCalendarIDs.isEmpty {
                    settings.selectedCalendarIDs = Set(eventStore.calendars.map(\.calendarIdentifier))
                }
                if settings.selectedCalendarIDs.contains(identifier) { settings.selectedCalendarIDs.remove(identifier) }
                else { settings.selectedCalendarIDs.insert(identifier) }
                if settings.selectedCalendarIDs.count == eventStore.calendars.count { settings.selectedCalendarIDs.removeAll() }
            }
        }
    }
    @objc private func soundToggled(_ sender: NSSwitch) { scheduler.updateSettings { $0.playSound = sender.state == .on } }
    @objc private func testAlert(_ sender: NSButton) { scheduler.testAlert() }
    @objc private func requestPermission(_ sender: NSButton) { scheduler.requestPermissionAgain() }
    @objc private func togglePause(_ sender: NSButton) {
        scheduler.setPaused(for: scheduler.pausedUntil.map { $0 > Date() } == true ? nil : HeadsUpConfiguration.pauseInterval)
    }
    @objc private func loginToggled(_ sender: NSSwitch) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
            NSAlert(error: error).runModal()
        }
    }
    @objc private func quit(_ sender: NSButton) { NSApp.terminate(nil) }

    private func addSection(_ text: String, at y: CGFloat) -> CGFloat {
        addLabel(text, x: 18, y: y, width: width - 36, height: 14, size: 11, weight: .semibold, color: .tertiaryLabelColor)
        return y + 18
    }

    private func card(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, highlighted: Bool = false) -> CardView {
        let result = CardView(frame: NSRect(x: x, y: y, width: width, height: height))
        result.wantsLayer = true
        result.highlighted = highlighted
        root.addSubview(result)
        return result
    }

    @discardableResult
    private func addSwitch(_ title: String, detail: String? = nil, y: CGFloat, in parent: NSView, action: Selector) -> NSSwitch {
        let label = addLabel(title, in: parent, x: 12, y: y, width: 220, height: 22, size: 12)
        if let detail { _ = addLabel(detail, in: parent, x: 12, y: y + 23, width: 250, height: 15, size: 10, color: .secondaryLabelColor) }
        let result = NSSwitch()
        result.target = self
        result.action = action
        let intrinsicSize = result.intrinsicContentSize
        let switchWidth = intrinsicSize.width > 0 ? intrinsicSize.width : 38
        let switchHeight = intrinsicSize.height > 0 ? intrinsicSize.height : 22
        result.frame = NSRect(
            x: parent.frame.width - switchWidth - 12,
            y: y + (22 - switchHeight) / 2,
            width: switchWidth,
            height: switchHeight
        )
        parent.addSubview(result)
        label.toolTip = detail
        return result
    }

    @discardableResult
    private func addLabel(_ text: String, in parent: NSView? = nil, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let result = NSTextField(labelWithString: text)
        result.font = .systemFont(ofSize: size, weight: weight)
        result.textColor = color
        result.lineBreakMode = .byTruncatingTail
        result.frame = NSRect(x: x, y: y, width: width, height: height)
        (parent ?? root).addSubview(result)
        return result
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
