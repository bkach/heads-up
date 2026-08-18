import AppKit
import Foundation

@MainActor
final class AlertPresenter: NSObject {
    private var windows: [NSWindow] = []
    private var event: MeetingEvent?
    private var countdownTimer: Timer?
    private var countdownLabels: [NSTextField] = []
    private let scheduler: ReminderScheduler

    init(scheduler: ReminderScheduler) {
        self.scheduler = scheduler
        super.init()
    }

    func show(_ event: MeetingEvent) {
        closeWindows()
        self.event = event
        let screens = scheduler.settings.showOnEveryDisplay
            ? NSScreen.screens
            : [NSScreen.main ?? NSScreen.screens.first].compactMap { $0 }
        windows = screens.map { makeWindow(for: event, screen: $0) }
        for (index, window) in windows.enumerated() {
            if index == 0 {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
        if scheduler.settings.playSound { NSSound(named: HeadsUpConfiguration.alertSoundName)?.play() }
        updateCountdown()
        countdownTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateCountdown), userInfo: nil, repeats: true)
    }

    private func makeWindow(for event: MeetingEvent, screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = NSColor.black.withAlphaComponent(0.72)
        window.isOpaque = false
        window.hasShadow = false
        window.canHide = false
        window.hidesOnDeactivate = false

        let root = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        let panelWidth: CGFloat = min(600, max(460, screen.frame.width * 0.44))
        let panelHeight: CGFloat = 310
        let panel = AlertCard(frame: NSRect(
            x: (screen.frame.width - panelWidth) / 2,
            y: (screen.frame.height - panelHeight) / 2,
            width: panelWidth,
            height: panelHeight
        ))
        panel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        root.addSubview(panel)

        let mark = NSImageView(frame: NSRect(x: (panelWidth - 34) / 2, y: panelHeight - 58, width: 34, height: 34))
        mark.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Meeting alert")
        mark.contentTintColor = HeadsUpStyle.accent
        panel.addSubview(mark)

        let title = label(event.title, size: 28, weight: .semibold, color: .labelColor)
        title.alignment = .center
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 28, y: panelHeight - 112, width: panelWidth - 56, height: 38)
        panel.addSubview(title)

        let countdown = label("", size: 16, weight: .medium, color: .secondaryLabelColor)
        countdown.alignment = .center
        countdown.frame = NSRect(x: 28, y: panelHeight - 148, width: panelWidth - 56, height: 24)
        panel.addSubview(countdown)
        countdownLabels.append(countdown)

        let primary = NSButton(title: event.joinURL == nil ? "Open Calendar" : "Join meeting", target: self, action: #selector(join))
        primary.bezelStyle = .rounded
        primary.controlSize = .large
        primary.keyEquivalent = "\r"
        primary.frame = NSRect(x: panelWidth / 2 - 152, y: 70, width: 190, height: 42)
        panel.addSubview(primary)

        let snooze = NSButton(title: "Snooze 1m", target: self, action: #selector(snooze))
        snooze.bezelStyle = .rounded
        snooze.controlSize = .large
        snooze.keyEquivalent = "s"
        snooze.frame = NSRect(x: panelWidth / 2 + 48, y: 70, width: 130, height: 42)
        panel.addSubview(snooze)

        let skip = NSButton(title: "Skip this meeting", target: self, action: #selector(skip))
        skip.bezelStyle = .inline
        skip.contentTintColor = .secondaryLabelColor
        skip.keyEquivalent = "\u{1b}"
        skip.frame = NSRect(x: (panelWidth - 150) / 2, y: 28, width: 150, height: 24)
        panel.addSubview(skip)

        if let host = event.joinURL?.host {
            primary.toolTip = "Open \(host)"
        }
        return window
    }

    @objc private func join() {
        guard let event else { return }
        if let url = event.joinURL {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple-calevent://")!)
        }
        scheduler.acknowledge(event)
        closeWindows()
    }

    @objc private func snooze() {
        guard let event else { return }
        scheduler.snooze(event)
        closeWindows()
    }

    @objc private func skip() {
        guard let event else { return }
        scheduler.acknowledge(event)
        closeWindows()
    }

    @objc private func updateCountdown() {
        guard let event else { return }
        let delta = event.startDate.timeIntervalSinceNow
        let text: String
        if delta > 1 {
            let seconds = Int(delta.rounded(.up))
            text = seconds >= 60
                ? "starts in \(seconds / 60)m \(seconds % 60)s"
                : "starts in \(seconds)s"
        } else if event.endDate > Date() {
            text = "starting now"
        } else {
            text = "meeting ended"
        }
        countdownLabels.forEach { $0.stringValue = text }
    }

    private func closeWindows() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        countdownLabels.removeAll()
        event = nil
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let result = NSTextField(labelWithString: text)
        result.font = .systemFont(ofSize: size, weight: weight)
        result.textColor = color
        return result
    }
}

private final class AlertCard: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = HeadsUpStyle.accent.withAlphaComponent(0.55).cgColor
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
