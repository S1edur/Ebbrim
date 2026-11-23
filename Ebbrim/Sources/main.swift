import AppKit
import SwiftUI
import Combine
import QuartzCore
import ServiceManagement

enum Edge: String { case left, right, bottom }
/// Which hover panel is open: one per provider, or the local servers.
/// `.settings` = the cursor is on the gear chip: the pill stays open, no card.
enum ActivePanel: Hashable { case none, provider(ProviderKind), servers, settings }

final class NotchModel: ObservableObject {
    @Published var active: ActivePanel = .none
    @Published var edge: Edge = .right
    @Published var centerFrac: CGFloat = 0.5
    @Published var dragging = false
    /// While dragged: the pill's center (panel-local, top-left) and the edge
    /// it would dock to if released now.
    @Published var dragCenter: CGPoint = .zero
    @Published var dragEdge: Edge = .right
    /// Rendered height of each hover panel, so the island and the hit area
    /// match the content exactly.
    @Published var tipH: [ActivePanel: CGFloat] = [:]
    /// Part of tipH that was added at the card's bottom (e.g. an explainer):
    /// the card keeps its top where it was and grows downward by this much.
    @Published var tipGrow: [ActivePanel: CGFloat] = [:]
    /// Providers the user turned off in the notch (Settings), and whether the
    /// servers chip shows. Mirrored into NotchLayout so view and hit-testing agree.
    @Published var hiddenKinds: Set<ProviderKind> = [] {
        didSet { NotchLayout.hiddenKinds = hiddenKinds
                 UserDefaults.standard.set(hiddenKinds.map(\.rawValue), forKey: "notch.hidden") }
    }

    var expanded: Bool { active != .none }

    func load() {
        let d = UserDefaults.standard
        if let e = d.string(forKey: "notch.edge"), let ed = Edge(rawValue: e) { edge = ed }
        if d.object(forKey: "notch.frac") != nil { centerFrac = CGFloat(d.double(forKey: "notch.frac")) }
        hiddenKinds = Set((d.stringArray(forKey: "notch.hidden") ?? []).compactMap(ProviderKind.init(rawValue:)))
    }
    func save() {
        let d = UserDefaults.standard
        d.set(edge.rawValue, forKey: "notch.edge")
        d.set(Double(centerFrac), forKey: "notch.frac")
    }
}

/// Full-height edge panel that is click-through everywhere EXCEPT the small icon
/// band (always) and the tooltip rect (while expanded). Uses the live cursor to
/// decide, so a tall tooltip can extend anywhere on screen without the window
/// swallowing clicks elsewhere.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var shouldCapture: (NSPoint) -> Bool = { _ in false }   // screen point
    var overIcon: (NSPoint) -> Bool = { _ in false }        // screen point
    var onDragBegan: ((NSPoint) -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    /// A press on the pill that didn't become a drag (screen point).
    var onClick: ((NSPoint) -> Void)?
    private var pressAt: NSPoint?            // mouse down on the pill, not yet a drag
    private var dragging = false

    /// The panel never becomes key: take the very first click (the gear)
    /// instead of spending it on focusing the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        shouldCapture(NSEvent.mouseLocation) ? self : nil
    }
    override func mouseDown(with e: NSEvent) {
        if overIcon(NSEvent.mouseLocation) { pressAt = NSEvent.mouseLocation }
        else { super.mouseDown(with: e) }
    }
    override func mouseDragged(with e: NSEvent) {
        let p = NSEvent.mouseLocation
        if let a = pressAt, !dragging, hypot(p.x - a.x, p.y - a.y) > 3 {
            dragging = true; onDragBegan?(a)
        }
        if dragging { onDragMoved?(p) } else if pressAt == nil { super.mouseDragged(with: e) }
    }
    override func mouseUp(with e: NSEvent) {
        let pressed = pressAt != nil
        pressAt = nil
        if dragging { dragging = false; onDragEnded?(NSEvent.mouseLocation) }
        else if pressed { onClick?(NSEvent.mouseLocation) }
        else { super.mouseUp(with: e) }
    }
}

/// The edge-notch display: a full-screen, click-through panel. The pill rides
/// its edge at model.centerFrac; drag it off and drop it on another edge.
final class NotchController {
    let model = NotchModel()
    private let activity: ActivityTracker
    private let panel: NSPanel
    private let feed: UsageFeed
    private let servers: ServerStore
    private var settingsSink: AnyCancellable?
    private var grab: CGPoint = .zero         // cursor offset from the pill center while dragging
    private var monitors: [Any] = []
    private var closeWork: DispatchWorkItem?

    init(feed: UsageFeed, servers: ServerStore) {
        self.feed = feed
        self.servers = servers
        self.activity = ActivityTracker(feed: feed)
        model.load()
        let f = Self.screenFrame()
        panel = NSPanel(contentRect: f,
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let view = NotchView(feed: feed, activity: activity, servers: servers, model: model,
                             onOpen: { [weak self] s in self?.servers.open(s) },
                             onKill: { [weak self] s in self?.confirmKill(s) })
        let host = PassthroughHostingView(rootView: view)
        host.shouldCapture = { [weak self] p in self?.shouldCapture(p) ?? false }
        host.overIcon = { [weak self] p in self?.iconBand().contains(p) ?? false }
        host.onDragBegan = { [weak self] p in self?.beginDrag(at: p) }
        host.onDragMoved = { [weak self] p in self?.dragTo(p) }
        host.onDragEnded = { [weak self] _ in self?.endDrag() }
        host.onClick = { [weak self] p in self?.click(at: p) }
        panel.contentView = host
        reposition()
        panel.orderFrontRegardless()
        // The servers chip follows the data layer's switch (Settings › Appearance).
        settingsSink = feed.$settings.sink { [weak self] s in
            NotchLayout.showServers = s.serversEnabled
            NotchLayout.disabledKinds = Set([s.claudeEnabled ? nil : ProviderKind.claude,
                                             s.codexEnabled ? nil : ProviderKind.codex].compactMap { $0 })
            self?.model.objectWillChange.send()
        }

        let handler: (NSEvent?) -> Void = { [weak self] _ in self?.updateHover() }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { handler($0) }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { handler($0); return $0 }) { monitors.append(l) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.reposition() }
    }

    func setEdge(_ e: Edge) {
        withAnimation(.spring(duration: 0.5, bounce: 0.24)) { model.edge = e }
        model.save()
    }

    private static func screenFrame() -> NSRect { (NSScreen.main ?? NSScreen.screens.first!).frame }

    private func reposition() {
        panel.setFrame(Self.screenFrame(), display: true)
    }

    // MARK: geometry — derived from NotchLayout, the same source the view uses
    // to place things, so hit-testing always matches what's drawn.
    private var hovering: Bool { model.expanded && !model.dragging }
    private var horizontal: Bool { NotchLayout.horizontal(model.edge) }
    private func items() -> [NotchLayout.PillItem] {
        NotchLayout.items(feed.providers, hovering: hovering)
    }
    /// Screen point → panel-local (top-left origin).
    private func local(_ p: NSPoint) -> CGPoint {
        let pf = panel.frame
        return CGPoint(x: p.x - pf.minX, y: pf.maxY - p.y)
    }
    /// Panel-local rect → screen rect.
    private func screen(_ r: CGRect) -> NSRect {
        let pf = panel.frame
        return NSRect(x: pf.minX + r.minX, y: pf.maxY - r.maxY, width: r.width, height: r.height)
    }
    private func pillLocal() -> CGRect {
        NotchLayout.pillRect(edge: model.edge, providers: feed.providers, hovering: hovering,
                             frac: model.centerFrac, size: panel.frame.size)
    }
    /// The pill plus a little slack on its inner side.
    private func iconBand() -> NSRect {
        var r = pillLocal()
        let s: CGFloat = 12
        switch model.edge {
        case .left: r.size.width += s
        case .right: r.origin.x -= s; r.size.width += s
        case .bottom: r.origin.y -= s; r.size.height += s
        }
        return screen(r)
    }
    private func tooltipScreenRect() -> NSRect? {
        guard model.expanded, model.active != .settings else { return nil }
        return screen(NotchLayout.cardRect(active: model.active, edge: model.edge, providers: feed.providers,
                                           hovering: hovering, serverCount: servers.servers.count,
                                           measured: model.tipH[model.active],
                                           grow: model.tipGrow[model.active] ?? 0, frac: model.centerFrac,
                                           size: panel.frame.size))
    }
    private func inTooltip(_ p: NSPoint) -> Bool {
        tooltipScreenRect().map { $0.insetBy(dx: -12, dy: -12).contains(p) } ?? false
    }
    private func shouldCapture(_ p: NSPoint) -> Bool {
        iconBand().contains(p) || inTooltip(p)
    }

    // MARK: drag — the pill lifts off as a free capsule, follows the cursor and
    // reshapes for the nearest edge; on release it docks there.
    private func beginDrag(at p: NSPoint) {
        setActive(.none)
        let r = NotchLayout.pillRect(edge: model.edge, providers: feed.providers, hovering: false,
                                     frac: model.centerFrac, size: panel.frame.size)
        let c = CGPoint(x: r.midX, y: r.midY), lp = local(p)
        grab = CGPoint(x: lp.x - c.x, y: lp.y - c.y)
        model.dragEdge = model.edge
        model.dragCenter = c
        model.dragging = true
    }

    private func dragTo(_ p: NSPoint) {
        let lp = local(p), size = panel.frame.size
        model.dragCenter = CGPoint(x: lp.x - grab.x, y: lp.y - grab.y)
        // Nearest edge to the cursor (top is the menu bar: not a dock).
        let d: [(Edge, CGFloat)] = [(.left, lp.x), (.right, size.width - lp.x), (.bottom, size.height - lp.y)]
        let e = d.min { $0.1 < $1.1 }!.0
        if e != model.dragEdge { model.dragEdge = e }
    }

    private func endDrag() {
        let size = panel.frame.size, c = model.dragCenter
        let e = model.dragEdge
        let f = NotchLayout.horizontal(e) ? c.x / size.width : 1 - c.y / size.height
        model.edge = e
        model.centerFrac = NotchLayout.clampFrac(f)
        model.dragging = false
        model.save()
    }

    private func updateHover() {
        if model.dragging { return }
        let p = NSEvent.mouseLocation
        if iconBand().contains(p) {
            // Over the notch: every block (each provider, the servers chip) is
            // its own zone and opens its own panel. Re-evaluated on every move,
            // with hysteresis so resting near a boundary can't flicker.
            cancelClose()
            let lp = local(p), pr = pillLocal()
            let along = horizontal ? lp.x - pr.minX : lp.y - pr.minY
            if let it = NotchLayout.item(at: along, items(), current: model.active, horizontal) {
                setActive(it.panel)
            }
        } else if model.expanded {
            if inTooltip(p) { cancelClose() } else { scheduleClose() }
        }
    }

    /// Close after a short grace period, so crossing the small gap between the
    /// notch and the tooltip doesn't dismiss it.
    private func scheduleClose() {
        guard closeWork == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            guard let s = self else { return }
            s.closeWork = nil
            let p = NSEvent.mouseLocation
            if !s.iconBand().contains(p) && !s.inTooltip(p) { s.setActive(.none) }
        }
        closeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }
    private func cancelClose() { closeWork?.cancel(); closeWork = nil }

    /// A click on the pill: the gear opens Settings.
    private func click(at p: NSPoint) {
        let lp = local(p), pr = pillLocal()
        let along = horizontal ? lp.x - pr.minX : lp.y - pr.minY
        switch NotchLayout.item(at: along, items(), current: model.active, horizontal) {
        case .settings?, .setup?:              // gear, or "+" on a source still to set up
            setActive(.none)
            openSettings()
        case .connect(let k)?:                 // "+ Claude" / "+ Codex": reconnect right here
            feed.perform(k == .claude ? .setClaude(true) : .setCodex(true))
        default:
            break
        }
    }

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    /// Settings: sources (connect / disconnect), Open at Login, edge.
    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = Self.window(title: "Settings", size: NSSize(width: 560, height: 600), plainTitleBar: true,
                                         root: SettingsView(
                feed: feed, model: model,
                onEdge: { [weak self] e in self?.setEdge(e) },
                onRefresh: { [weak self] in self?.feed.requestRefresh() },
                onWelcome: { [weak self] in self?.openOnboarding() }))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// The welcome tour (first launch, or "Show the welcome tour" in Settings).
    func openOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = Self.window(title: "Welcome to Ebbrim", size: NSSize(width: 860, height: 540),
                                           root: OnboardingView(
                feed: feed, model: model,
                onEdge: { [weak self] e in self?.setEdge(e) },
                onFinish: { [weak self] in
                    UserDefaults.standard.set(true, forKey: "onboarded")
                    self?.onboardingWindow?.close()
                }))
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    /// A dark window. Onboarding runs under a transparent title bar; Settings
    /// keeps a plain one (its title shows, its list scrolls below it).
    private static func window<V: View>(title: String, size: NSSize, plainTitleBar: Bool = false,
                                        root: V) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: plainTitleBar ? [.titled, .closable] : [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = title
        w.titleVisibility = plainTitleBar ? .visible : .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(white: 0.055, alpha: 1)
        let host = NSHostingView(rootView: root)
        // Under a transparent title bar the view fills the window as it is:
        // no safe-area inset (which also grew the window and cut the bottom).
        if !plainTitleBar { host.safeAreaRegions = [] }
        w.contentView = host
        w.center()
        return w
    }

    private func setActive(_ v: ActivePanel) {
        guard model.active != v else { return }
        model.active = v
    }

    /// Confirm before killing — it's terminating the user's own process.
    private func confirmKill(_ s: LocalServer) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Stop this server?"
        a.informativeText = "\(s.project) · \(s.kind) on :\(s.port)\nProcess \(s.pid) will be asked to quit (SIGTERM)."
        a.addButton(withTitle: "Stop")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        if a.runModal() == .alertFirstButtonReturn { servers.terminate(s) }
    }
}

/// The menu-bar control: refresh, position, sources, launch at login, access
/// info, quit — the "control" the notch itself doesn't provide.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let feed: UsageFeed
    private weak var notch: NotchController?
    private weak var app: AppDelegate?

    init(feed: UsageFeed, notch: NotchController, app: AppDelegate) {
        self.feed = feed; self.notch = notch; self.app = app
        super.init()
        item.button?.image = Self.markIcon()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let used = feed.providers.first { $0.kind == .claude }?.headlineUsed
        menu.addItem(header(used.map { "Claude — \(Int($0.rounded()))% used" } ?? "Ebbrim"))
        menu.addItem(.separator())
        menu.addItem(action("Refresh", #selector(refresh)))
        let pos = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.addItem(action("Right", #selector(edgeRight)))
        sub.addItem(action("Left", #selector(edgeLeft)))
        sub.addItem(action("Bottom", #selector(edgeBottom)))
        pos.submenu = sub
        menu.addItem(pos)
        menu.addItem(.separator())
        menu.addItem(toggle("Show Codex", on: feed.settings.codexEnabled, #selector(toggleCodex)))
        menu.addItem(toggle("Claude Code in Terminal", on: feed.settings.terminalConnected, #selector(toggleTerminal)))
        menu.addItem(toggle("Open at Login", on: feed.settings.launchAtLogin, #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(action("Settings…", #selector(openSettings)))
        menu.addItem(action("About Access", #selector(showAbout)))
        menu.addItem(action("Uninstall Ebbrim…", #selector(uninstall)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Ebbrim", #selector(quit)))
    }

    private func header(_ s: String) -> NSMenuItem {
        let i = NSMenuItem(title: s, action: nil, keyEquivalent: ""); i.isEnabled = false; return i
    }
    private func action(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; return i
    }
    private func toggle(_ title: String, on: Bool, _ sel: Selector) -> NSMenuItem {
        let i = action(title, sel); i.state = on ? .on : .off; return i
    }

    @objc private func refresh() { feed.requestRefresh() }
    @objc private func edgeRight() { notch?.setEdge(.right) }
    @objc private func edgeLeft() { notch?.setEdge(.left) }
    @objc private func edgeBottom() { notch?.setEdge(.bottom) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    @objc private func showAbout() { app?.showAccessPanel() }
    @objc private func openSettings() { notch?.openSettings() }
    @objc private func uninstall() { feed.perform(.uninstall) }
    @objc private func toggleCodex() { feed.perform(.setCodex(!feed.settings.codexEnabled)) }
    @objc private func toggleTerminal() { feed.perform(.setTerminal(!feed.settings.terminalConnected)) }
    @objc private func toggleLogin() { feed.perform(.setLaunchAtLogin(!feed.settings.launchAtLogin)) }

    /// Monochrome Claude burst — a template icon that adapts to the menu bar.
    private static func markIcon() -> NSImage {
        let s: CGFloat = 15
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        let c = NSPoint(x: s / 2, y: s / 2)
        let r = s * 0.46
        NSColor.black.setStroke()
        for i in 0..<12 {
            let a = Double(i) / 12 * 2 * .pi
            let ray = NSBezierPath()
            ray.move(to: NSPoint(x: c.x + cos(a) * r * 0.15, y: c.y + sin(a) * r * 0.15))
            ray.line(to: NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            ray.lineWidth = r * 0.16
            ray.lineCapStyle = .round
            ray.stroke()
        }
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var notch: NotchController?
    var menu: StatusMenuController?
    let feed = UsageFeed.isMock ? UsageFeed.mock() : UsageFeed()
    let servers = ServerStore()
    private var aggregator: UsageAggregator?
    private var desktop: DesktopCacheSource?
    private var codex: CodexSource?
    private var terminal: StatusLineSource?

    var codexEnabled: Bool { flag("codexEnabled") }
    var claudeEnabled: Bool { flag("claudeEnabled") }
    var serversEnabled: Bool { flag("serversEnabled") }
    private func flag(_ key: String) -> Bool { SourceSwitches.isOn(key) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        retireOtherInstances()
        let n = NotchController(feed: feed, servers: servers)
        notch = n
        menu = StatusMenuController(feed: feed, notch: n, app: self)
        guard !UsageFeed.isMock else { servers.start(); return }
        if serversEnabled { servers.start() }
        feed.onAction = { [weak self] in self?.apply($0) }
        syncSettings()

        let agg = UsageAggregator(feed: feed, codexEnabled: { [weak self] in self?.codexEnabled ?? false },
                                  claudeEnabled: { [weak self] in self?.claudeEnabled ?? false })
        aggregator = agg
        desktop = DesktopCacheSource { agg.receive($0, from: .desktopCache) }
        terminal = StatusLineSource { agg.receive($0, from: .statusLine) }
        codex = CodexSource { agg.receive($0, from: .codex) }
        feed.onRefreshRequest = { [weak self] in
            self?.desktop?.readNow(); self?.terminal?.readNow(); self?.codex?.readNow()
        }
        agg.start()
        if claudeEnabled { desktop?.start(); terminal?.start() }
        if codexEnabled { codex?.start() }
        // Keep the out-of-bundle copy of statusline.sh in step with this build.
        if StatusLineInstaller.isInstalled(), let script = Bundle.main.path(forResource: "statusline", ofType: "sh") {
            _ = try? StatusLineInstaller.refreshScript(source: script)
        }

        // First run: the onboarding (UI) shows each source's state and sets
        // "onboarded" when the user finishes it.
        if !UserDefaults.standard.bool(forKey: "onboarded") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.notch?.openOnboarding() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        codex?.stop()                       // ends an in-flight Codex helper call
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notch?.openSettings()
        return false
    }

    /// Applies a switch change asked for by the menu or the Settings window,
    /// then publishes the real resulting state to `feed.settings`.
    func apply(_ action: FeedAction) {
        defer { syncSettings() }
        if let prompt = DisconnectPrompt.text(for: action) {
            let a = NSAlert()
            a.messageText = prompt.title
            a.informativeText = prompt.body
            a.addButton(withTitle: "Disconnect")
            a.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            switch action {
            case .setClaude(let on):
                UserDefaults.standard.set(on, forKey: "claudeEnabled")
                if on { desktop?.start(); terminal?.start() } else {
                    desktop?.stop(); terminal?.stop()
                    aggregator?.forget(.claude)
                }
                aggregator?.tick()
            case .setServers(let on):
                UserDefaults.standard.set(on, forKey: "serversEnabled")
                if on { servers.start() } else { servers.stop() }
            case .setCodex(let on):
                UserDefaults.standard.set(on, forKey: "codexEnabled")
                if on { codex?.start() } else { codex?.stop(); aggregator?.forget(.codex) }
                aggregator?.tick()
            case .setLaunchAtLogin(let on):
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            case .setTerminal(false):
                try StatusLineInstaller.uninstall()
                aggregator?.forget(source: .statusLine)
                desktop?.readNow()                  // Claude Desktop keeps feeding Claude
            case .setTerminal(true):
                guard !StatusLineInstaller.isInstalled(),
                      let script = Bundle.main.path(forResource: "statusline", ofType: "sh") else { return }
                let a = NSAlert()
                a.messageText = "Connect Claude Code in Terminal?"
                a.informativeText = """
                Ebbrim will add a statusLine to ~/.claude/settings.json that saves the limits \
                Claude Code already shows into Ebbrim's own folder. Your current statusLine \
                (if any) keeps working. You can disconnect here any time.
                """
                a.addButton(withTitle: "Connect")
                a.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                guard a.runModal() == .alertFirstButtonReturn else { return }
                try StatusLineInstaller.install(scriptSource: script)
                terminal?.readNow()
            case .uninstall:
                uninstallInteractively()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    /// Menu / Settings: confirm, remove every trace, trash the app, quit.
    private func uninstallInteractively() {
        let a = NSAlert()
        a.messageText = "Uninstall Ebbrim?"
        a.informativeText = """
        Ebbrim will:
        • disconnect Claude Code in Terminal and put back your previous statusLine
        • remove its login item, preferences and data folder
        • delete the downloaded source in ~/.ebbrim, if the one-line installer made it
        • move Ebbrim.app to the Trash

        Claude, Codex and your logins are not touched.
        """
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        codex?.stop(); desktop?.stop(); terminal?.stop(); servers.stop()
        let report = Uninstaller.cleanup(unregisterLoginItem: Self.unregisterLoginItem)
        let bundle = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([bundle]) { _, error in
            var problems = report.problems
            if let error { problems.append("Could not move Ebbrim.app to the Trash: \(error.localizedDescription)") }
            if !problems.isEmpty {
                let p = NSAlert()
                p.messageText = "Ebbrim was mostly removed"
                p.informativeText = problems.joined(separator: "\n")
                p.runModal()
            }
            exit(0)          // not terminate(): AppKit would write preferences back on the way out
        }
    }

    /// True when there was a login item and it is gone now.
    static func unregisterLoginItem() throws -> Bool {
        guard SMAppService.mainApp.status == .enabled else { return false }
        try SMAppService.mainApp.unregister()
        return true
    }

    private func syncSettings() {
        let now = FeedSettings(claudeEnabled: claudeEnabled, codexEnabled: codexEnabled,
                               terminalConnected: StatusLineInstaller.isInstalled(),
                               launchAtLogin: SMAppService.mainApp.status == .enabled,
                               serversEnabled: serversEnabled)
        if feed.settings != now { feed.settings = now }
    }

    func showAccessPanel() {
        let a = NSAlert()
        a.messageText = AccessText.title
        a.informativeText = AccessText.body(providers: feed.providers, codexEnabled: codexEnabled,
                                            terminalConnected: StatusLineInstaller.isInstalled(), now: Date())
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// One Ebbrim at a time: a newly launched copy replaces any running one.
    private func retireOtherInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: id)
        where other.processIdentifier != me {
            other.terminate()
        }
    }
}

// `Ebbrim --uninstall` (used by uninstall.sh): remove every trace, no UI.
if CommandLine.arguments.contains("--uninstall") {
    let report = Uninstaller.cleanup(unregisterLoginItem: AppDelegate.unregisterLoginItem)
    report.done.forEach { print("✓ \($0)") }
    report.problems.forEach { print("✗ \($0)") }
    exit(report.problems.isEmpty ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// `pkill` (install.sh) sends SIGTERM: quit through AppKit so cleanup runs.
signal(SIGTERM, SIG_IGN)
let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigterm.setEventHandler { NSApp.terminate(nil) }
sigterm.resume()
let delegate = AppDelegate()
app.delegate = delegate
app.run()
