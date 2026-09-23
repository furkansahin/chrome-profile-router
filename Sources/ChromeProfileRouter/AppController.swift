import AppKit
import RouterCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let catalog = ProfileCatalog()
    let settings = SettingsModel()
    lazy var settingsWindow = SettingsWindow(model: settings, catalog: catalog)
    let picker = PickerWindow()
    private var statusItem: NSStatusItem?
    private var queue = RequestQueue()
    private var inbox: [LinkRequest] = []
    private var intakeTask: Task<Void, Never>?
    private var classifyingRequest: LinkRequest?
    private var cancelledRequestIDs: Set<UUID> = []
    private var pumping = false
    private var selecting = false
    private var receivedURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:withReplyEvent:)),
                                                    forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenus()
        settingsWindow.onClose = { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                await self.catalog.refresh()
                self.pump()
            }
        }
        picker.model.choose = { [weak self] profile in self?.select(profile) }
        picker.model.cancel = { [weak self] in self?.cancel() }
        picker.model.retry = { [weak self] in self?.retry() }
        picker.model.copyLink = { [weak self] in
            guard let raw = self?.queue.first?.request.rawURL else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(raw, forType: .string)
        }
        picker.model.settings = { [weak self] in
            // Keep the request available while granting profile access in Settings.
            self?.picker.hide()
            self?.settingsWindow.show()
        }
        Task {
            await catalog.refresh()
            if !receivedURL && inbox.isEmpty && queue.count == 0 { settingsWindow.show() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !receivedURL || !picker.isVisible { settingsWindow.show() }
        return false
    }

    @objc private func becameActive() { settings.refreshStatus() }
    @objc func showSettings() { settingsWindow.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func installMenus() {
        let appMenu = NSMenu()
        let root = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        submenu.addItem(withTitle: "Quit Tabitat", action: #selector(quit), keyEquivalent: "q").target = self
        root.submenu = submenu
        appMenu.addItem(root)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (name, action, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: name, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = editMenu; appMenu.addItem(edit)
        NSApp.mainMenu = appMenu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
        item.button?.toolTip = "Tabitat"
        let menu = NSMenu()
        menu.delegate = self
        updateProfileMenu(menu)
        item.menu = menu
        statusItem = item
    }

    private func updateProfileMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let heading = menu.addItem(withTitle: "Open Chrome profile", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        if catalog.profiles.isEmpty {
            let unavailable = menu.addItem(withTitle: catalog.isRefreshing ? "Loading profiles…" : "No profiles available", action: nil, keyEquivalent: "")
            unavailable.isEnabled = false
            unavailable.toolTip = catalog.error
        }
        for profile in catalog.profiles {
            let entry = menu.addItem(withTitle: profile.label, action: #selector(openProfileFromMenu(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = profile.id
            entry.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)
            entry.toolTip = "Open \(profile.label) in Chrome"
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateProfileMenu(menu)
        // Refresh for the next opening without moving items under the pointer
        // while the current menu is being used. Dispatch revalidates the choice.
        Task { await catalog.refresh() }
    }

    @objc private func openProfileFromMenu(_ sender: NSMenuItem) {
        guard let profileID = sender.representedObject as? String else { return }
        Task {
            do {
                try await ChromeLauncher.open(profileID: profileID, catalog: catalog)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Couldn’t open Chrome profile"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Settings…")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn { settingsWindow.show() }
            }
        }
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let rawURL = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else { return }
        receivedURL = true
        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let sender = pid.flatMap { $0 > 0 ? NSRunningApplication(processIdentifier: $0) : nil }
        let cursor = NSEvent.mouseLocation
        let request = LinkRequest(rawURL: rawURL, sourceBundleID: sender?.bundleIdentifier, sourceName: sender?.localizedName,
                                  sourcePID: pid, cursorX: cursor.x, cursorY: cursor.y)
        enqueue(request)
    }

    func enqueue(_ request: LinkRequest) {
        inbox.append(request)
        guard intakeTask == nil else { return }
        intakeTask = Task {
            while !inbox.isEmpty {
                let request = inbox.removeFirst()
                classifyingRequest = request
                await catalog.refresh()
                let route = Router.route(request, workProfileID: settings.workProfileID, profiles: catalog.profiles,
                                         workSourceBundleIDs: Set(settings.workSourceApps.map(\.id)))
                classifyingRequest = nil
                if cancelledRequestIDs.remove(request.id) != nil && !route.isAutomatic { continue }
                queue.append(PendingRequest(request: request, route: route))
                picker.model.pendingCount = max(1, queue.pickerCount)
                pump()
            }
            intakeTask = nil
        }
    }

    private func pump() {
        guard !pumping, !picker.isVisible, !selecting else { return }
        pumping = true
        Task {
            defer { pumping = false }
            while let pending = queue.first {
                switch pending.route {
                case .automatic(let id):
                    guard let link = pending.request.link else {
                        queue.replaceFirstRoute(.invalid); continue
                    }
                    do {
                        try await ChromeLauncher.open(link, profileID: id, catalog: catalog)
                        queue.removeFirst(id: pending.request.id)
                    } catch {
                        queue.replaceFirstRoute(.picker(message: nil))
                        showPicker(for: pending.request, error: error.localizedDescription)
                        return
                    }
                case .picker(let message):
                    showPicker(for: pending.request, message: message, error: catalog.error)
                    return
                case .invalid:
                    showPicker(for: pending.request, error: "This isn’t a valid HTTP or HTTPS link.")
                    return
                }
            }
        }
    }

    private func showPicker(for request: LinkRequest, message: String? = nil, error: String? = nil) {
        picker.show(request: request, profiles: request.link == nil ? [] : catalog.profiles, message: message, error: error,
                    pendingCount: max(1, queue.pickerCount))
    }

    private func select(_ profile: ChromeProfile) {
        guard !selecting, let pending = queue.first, let link = pending.request.link else { return }
        selecting = true
        picker.hide()
        Task {
            do {
                try await ChromeLauncher.open(link, profileID: profile.id, catalog: catalog)
                queue.removeFirst(id: pending.request.id)
                selecting = false
                pump()
            } catch {
                selecting = false
                showPicker(for: pending.request, error: error.localizedDescription)
            }
        }
    }

    private func retry() {
        guard !selecting, let pending = queue.first else { return }
        picker.hide()
        selecting = true
        Task {
            await catalog.refresh()
            selecting = false
            showPicker(for: pending.request, error: catalog.error)
        }
    }

    private func cancel() {
        guard !selecting else { return }
        let sourcePID = queue.first?.request.sourcePID
        picker.hide()
        queue.cancelPickerRequests()
        cancelledRequestIDs.formUnion(inbox.map(\.id))
        if let request = classifyingRequest { cancelledRequestIDs.insert(request.id) }
        if let pid = sourcePID, let source = NSRunningApplication(processIdentifier: pid) {
            source.activate(options: [])
        }
        pump()
    }
}
