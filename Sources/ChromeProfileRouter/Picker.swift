import AppKit
import SwiftUI
import RouterCore

@MainActor
final class PickerModel: ObservableObject {
    @Published var profiles: [ChromeProfile] = []
    @Published var focusedIndex = 0
    @Published var hostname = "Choose a profile"
    @Published var sourceName: String?
    @Published var message: String?
    @Published var error: String?
    @Published var pendingCount = 1
    var choose: (ChromeProfile) -> Void = { _ in }
    var retry: () -> Void = {}
    var copyLink: () -> Void = {}
    var cancel: () -> Void = {}
    var settings: () -> Void = {}

    func keyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { cancel(); return true }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if let key = event.charactersIgnoringModifiers, let digit = Int(key), digit > 0, digit <= min(9, profiles.count) {
            choose(profiles[digit - 1]); return true
        }
        guard !profiles.isEmpty else { return false }
        switch event.keyCode {
        case 123, 124, 48:
            let backwards = event.keyCode == 123 || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
            focusedIndex = (focusedIndex + (backwards ? -1 : 1) + profiles.count) % profiles.count
            return true
        case 36, 76:
            choose(profiles[focusedIndex]); return true
        default: return false
        }
    }
}

struct AvatarView: View {
    let profile: ChromeProfile
    var size: CGFloat = 54
    @State private var image: NSImage?

    private var tint: Color {
        let colors: [Color] = [.indigo, .teal, .orange, .pink, .blue, .purple]
        let index = profile.id.utf8.reduce(0) { ($0 + Int($1)) % colors.count }
        return colors[index]
    }

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else {
                Circle().fill(tint.gradient)
                    .overlay(Text(profile.initials).font(.system(size: size * 0.32, weight: .semibold, design: .rounded)).foregroundStyle(.white))
            }
        }.frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .accessibilityHidden(true)
            .task(id: profile.avatarPath) {
                guard let path = profile.avatarPath else { image = nil; return }
                let data = await Task.detached(priority: .utility) { try? Data(contentsOf: URL(fileURLWithPath: path)) }.value
                image = data.flatMap { NSImage(data: $0) }
            }
    }
}

struct PickerView: View {
    @ObservedObject var model: PickerModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "link").font(.system(size: 11, weight: .medium))
                Text(model.hostname).lineLimit(1).truncationMode(.middle)
                if let source = model.sourceName { Text("·"); Text(source).lineLimit(1) }
                Spacer(minLength: 4)
                if model.pendingCount > 1 {
                    Text("\(model.pendingCount) pending").font(.system(size: 10, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 7)

            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 7)
            }

            if !model.profiles.isEmpty {
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: model.profiles.count > 7) {
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                                Button { model.choose(profile) } label: {
                                    VStack(spacing: 8) {
                                        AvatarView(profile: profile)
                                        Text(profile.label).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                            .multilineTextAlignment(.center).frame(height: 30, alignment: .top)
                                        Text(index < 9 ? String(index + 1) : " ")
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary).frame(width: 19, height: 17)
                                            .background(.primary.opacity(index < 9 ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 4))
                                    }
                                    .padding(.vertical, 12).frame(width: 102)
                                    .background(model.focusedIndex == index ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.focusedIndex == index ? Color.accentColor.opacity(0.42) : .clear, lineWidth: 1))
                                    .contentShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain).focusable(false)
                                .onHover { hovering in if hovering { model.focusedIndex = index } }
                                .accessibilityLabel("Open in \(profile.label)")
                                .accessibilityHint(index < 9 ? "Press \(index + 1)" : "")
                                .id(index)
                            }
                        }.padding(2)
                    }
                    .onChange(of: model.focusedIndex) { _, index in reader.scrollTo(index) }
                }
            }

            if let error = model.error {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "exclamationmark.circle").font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Retry", action: model.retry)
                        Button("Copy Link", action: model.copyLink)
                        Button("Settings…", action: model.settings)
                        Spacer()
                        Button("Cancel", action: model.cancel)
                    }.controlSize(.small)
                }.padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .padding(1)
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PickerWindow: NSObject, NSWindowDelegate {
    let model = PickerModel()
    private var panel: PickerPanel?
    private var keyMonitor: Any?
    private var outsideMonitor: Any?
    private var localMouseMonitor: Any?
    private var suppressResign = false
    var isVisible: Bool { panel?.isVisible == true }

    func show(request: LinkRequest, profiles: [ChromeProfile], message: String?, error: String?, pendingCount: Int) {
        hide()
        model.profiles = profiles
        model.focusedIndex = 0
        model.hostname = request.link?.hostname ?? "This link can’t be opened"
        model.sourceName = request.sourceName
        model.message = message
        model.error = error
        model.pendingCount = pendingCount

        let cursor = NSPoint(x: request.cursorX, y: request.cursorY)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let width = min(max(CGFloat(profiles.count) * 108 + 32, error == nil ? 260 : 480), min(800, screen.visibleFrame.width - 24))
        let controller = NSHostingController(rootView: PickerView(model: model).frame(width: width))
        let size = controller.view.fittingSize
        let height = max(size.height, 120)
        let frame = NSRect(x: min(max(cursor.x - width / 2, screen.visibleFrame.minX + 12), screen.visibleFrame.maxX - width - 12),
                           y: min(max(cursor.y - height - 14, screen.visibleFrame.minY + 12), screen.visibleFrame.maxY - height - 12),
                           width: width, height: height)
        let panel = PickerPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = controller
        panel.setFrame(frame, display: true)
        panel.delegate = self
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.model.keyDown(event) ? nil : event
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.model.cancel()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window != self.panel else { return event }
            self.model.cancel()
            return event
        }
    }

    func hide() {
        suppressResign = true
        for monitor in [keyMonitor, outsideMonitor, localMouseMonitor] { if let monitor { NSEvent.removeMonitor(monitor) } }
        keyMonitor = nil; outsideMonitor = nil; localMouseMonitor = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        suppressResign = false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !suppressResign, isVisible else { return }
        model.cancel()
    }
}
