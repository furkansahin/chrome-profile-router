import AppKit
import SwiftUI
import ServiceManagement
import RouterCore
import UniformTypeIdentifiers

@MainActor
final class SettingsModel: ObservableObject {
    @Published var workProfileID: String {
        didSet { UserDefaults.standard.set(workProfileID, forKey: "workProfileID") }
    }
    @Published private(set) var workSourceApps: [WorkSourceApp] {
        didSet {
            if let data = try? JSONEncoder().encode(workSourceApps) {
                UserDefaults.standard.set(data, forKey: "workSourceApps")
            }
        }
    }
    @Published private(set) var isDefault = false
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published var error: String?
    @Published var settingDefault = false

    init() {
        workProfileID = UserDefaults.standard.string(forKey: "workProfileID") ?? ""
        workSourceApps = WorkSourceApp.restore(UserDefaults.standard.data(forKey: "workSourceApps"))
        refreshStatus()
    }

    func removeSource(_ app: WorkSourceApp) { workSourceApps.removeAll { $0.id == app.id } }

    func addSources() async {
        let panel = NSOpenPanel()
        panel.title = "Open links from these apps in Work"
        panel.prompt = "Add apps"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        guard await panel.begin() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
                error = "That app could not be identified. Choose a macOS application."
                continue
            }
            guard !workSourceApps.contains(where: { $0.id == id }) else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            workSourceApps.append(WorkSourceApp(id: id, name: name))
        }
    }

    func refreshStatus() {
        isDefault = ["http", "https"].allSatisfy { scheme in
            guard let url = URL(string: "\(scheme)://example.com"), let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
            return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setDefault() async {
        settingDefault = true
        error = nil
        defer { settingDefault = false; refreshStatus() }
        do {
            for scheme in ["http", "https"] {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            }
        } catch { self.error = "Link handling wasn’t enabled. \(error.localizedDescription)" }
    }

    func setLogin(_ enabled: Bool) async {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        } catch { self.error = "Launch at login couldn’t be changed. \(error.localizedDescription)" }
        refreshStatus()
    }

    func finishInitialSetup() async {
        guard !UserDefaults.standard.bool(forKey: "initialSetupComplete") else { return }
        UserDefaults.standard.set(true, forKey: "initialSetupComplete")
        await setLogin(true)
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var catalog: ProfileCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chrome Profile Router").font(.system(size: 21, weight: .semibold))
                    Text("The right profile, every time.").foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                settingRow {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Work profile").fontWeight(.medium)
                        Text("For links from the apps listed below.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Work profile", selection: $model.workProfileID) {
                        Text("Always ask").tag("")
                        ForEach(catalog.profiles) { profile in Text(profile.label).tag(profile.id) }
                        if !model.workProfileID.isEmpty && !catalog.profiles.contains(where: { $0.id == model.workProfileID }) {
                            Text("Unavailable profile").tag(model.workProfileID)
                        }
                    }.labelsHidden().frame(width: 190).disabled(catalog.profiles.isEmpty)
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Open in Work").fontWeight(.medium)
                        Spacer()
                        Button("Add apps…") { Task { await model.addSources() } }.controlSize(.small)
                    }
                    if model.workSourceApps.isEmpty {
                        Text("No apps added. All external links will ask for a profile.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(model.workSourceApps) { app in
                                    HStack(spacing: 9) {
                                        SourceAppIcon(bundleID: app.id)
                                        Text(app.name).font(.callout)
                                        Spacer()
                                        Button { model.removeSource(app) } label: {
                                            Image(systemName: "minus.circle").foregroundStyle(.secondary)
                                        }.buttonStyle(.plain).accessibilityLabel("Remove \(app.name) from Work apps")
                                    }.frame(height: 28)
                                }
                            }
                        }.frame(height: min(CGFloat(model.workSourceApps.count) * 34 - 6, 130))
                    }
                }.padding(.horizontal, 16).padding(.vertical, 15)
                Divider()
                settingRow {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Other links").fontWeight(.medium)
                        Text("Choose a Chrome profile each time.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("Ask each time", systemImage: "rectangle.grid.1x2").font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                settingRow {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Link handling").fontWeight(.medium)
                        Label(model.isDefault ? "Active" : "Not enabled", systemImage: model.isDefault ? "checkmark.circle.fill" : "circle")
                            .font(.caption).foregroundStyle(model.isDefault ? .green : .secondary)
                    }
                    Spacer()
                    if !model.isDefault {
                        Button(model.settingDefault ? "Enabling…" : "Enable link handling") {
                            Task { await model.setDefault() }
                        }.disabled(model.settingDefault || catalog.profiles.isEmpty)
                    }
                }
                Divider()
                settingRow {
                    Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { value in Task { await model.setLogin(value) } }))
                        .toggleStyle(.switch).controlSize(.small)
                }
            }
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))

            if let error = catalog.error {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "folder.badge.questionmark").font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Allow Chrome profiles…") { Task { await catalog.grantAccess() } }.buttonStyle(.borderedProminent)
                        Button("Retry") { Task { await catalog.refresh() } }
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack {
                    Text(catalog.isRefreshing ? "Looking for Chrome profiles…" : "\(catalog.profiles.count) Chrome profiles available")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { Task { await catalog.refresh() } }.controlSize(.small)
                }
            }
            if model.loginNeedsApproval {
                Button("Allow launch at login in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Text("Links inside Chrome keep working normally. To stop routing, choose Chrome as your default browser in System Settings.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(26).frame(width: 556)
        .task { await catalog.refresh(); model.refreshStatus() }
        .onChange(of: model.workProfileID) { _, value in
            if !value.isEmpty { Task { await model.finishInitialSetup() } }
        }
    }

    private func settingRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack { content() }.padding(.horizontal, 16).padding(.vertical, 15)
    }
}

private struct SourceAppIcon: View {
    let bundleID: String
    var body: some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
            }
        }.frame(width: 22, height: 22).accessibilityHidden(true)
    }
}

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    var onClose: () -> Void = {}
    private var window: NSWindow?
    private let model: SettingsModel
    private let catalog: ProfileCatalog
    init(model: SettingsModel, catalog: ProfileCatalog) { self.model = model; self.catalog = catalog; super.init() }

    func show() {
        if window == nil {
            let content = NSHostingController(rootView: SettingsView(model: model, catalog: catalog))
            let window = NSWindow(contentViewController: content)
            window.title = "Chrome Profile Router"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        model.refreshStatus()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        Task { await catalog.refresh() }
    }

    func windowWillClose(_ notification: Notification) { onClose() }
}
