import AppKit

@main
@MainActor
final class HeadsUpApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let eventStore = EventStoreService()
    private lazy var scheduler = ReminderScheduler(eventStore: eventStore)
    private lazy var alertPresenter = AlertPresenter(scheduler: scheduler)
    private lazy var popoverController = PopoverController(scheduler: scheduler, eventStore: eventStore)
    private var uiTestWindow: NSWindow?
    private var stateObserver: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = HeadsUpApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isUITest = CommandLine.arguments.contains("--ui-test-window")
        let isPopoverTest = CommandLine.arguments.contains("--show-popover")
        NSApp.setActivationPolicy(isUITest || isPopoverTest ? .regular : .accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        updateStatusIcon()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverController

        scheduler.onAlert = { [weak self] event in self?.alertPresenter.show(event) }
        stateObserver = NotificationCenter.default.addObserver(
            forName: .headsUpStateChanged,
            object: scheduler,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateStatusIcon() } }
        Task { await scheduler.start() }

        if isUITest {
            let window = NSWindow(contentViewController: popoverController)
            window.title = "Heads Up UI Test"
            window.styleMask = [.titled, .closable]
            window.setContentSize(popoverController.preferredContentSize)
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            uiTestWindow = window
        }

        // Hidden smoke-test hooks keep visual QA deterministic without adding debug controls to
        // the product UI. They are only acted on when explicitly passed at process launch.
        if CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.openPopover() }
        }
        if CommandLine.arguments.contains("--test-alert") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.scheduler.testAlert() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
    }

    @objc private func statusClicked() {
        if popover.isShown { closePopover() }
        else { openPopover() }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func updateStatusIcon() {
        let name: String
        let tint: NSColor?
        switch scheduler.health {
        case .permissionRequired, .failed:
            name = "calendar.badge.exclamationmark"
            tint = .systemRed
        default:
            if scheduler.settings.alertsEnabled, scheduler.pausedUntil.map({ $0 > Date() }) != true {
                name = "calendar.badge.clock"
                tint = HeadsUpStyle.accent
            } else {
                name = "calendar"
                tint = nil
            }
        }
        statusItem.button?.image = makeStatusImage(symbol: name, tint: tint)
        statusItem.button?.contentTintColor = nil
        statusItem.button?.toolTip = tooltipText()
    }

    private func makeStatusImage(symbol: String, tint: NSColor?) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let source = NSImage(systemSymbolName: symbol, accessibilityDescription: "Heads Up")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        guard let tint else {
            source.isTemplate = true
            return source
        }
        let result = NSImage(size: source.size)
        result.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: source.size))
        tint.set()
        NSRect(origin: .zero, size: source.size).fill(using: .sourceAtop)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    private func tooltipText() -> String {
        if let next = scheduler.events.first {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Heads Up · \(next.title) at \(formatter.string(from: next.startDate))"
        }
        return "Heads Up · No upcoming meetings"
    }
}
