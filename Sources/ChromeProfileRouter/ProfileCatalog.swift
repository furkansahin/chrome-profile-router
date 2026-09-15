import AppKit
import RouterCore

@MainActor
final class ProfileCatalog: ObservableObject {
    static var standardRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }
    @Published private(set) var profiles: [ChromeProfile] = []
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false
    private var accessURL: URL?
    private var accessed = false
    private var refreshTask: Task<[ChromeProfile], Error>?

    init() { restoreAccess() }

    func restoreAccess() {
        guard let data = UserDefaults.standard.data(forKey: "chromeFolderBookmark") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.standardizedFileURL.resolvingSymlinksInPath() == Self.standardRoot.standardizedFileURL.resolvingSymlinksInPath() else { return }
        accessURL = url
        accessed = url.startAccessingSecurityScopedResource()
        if stale, let replacement = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(replacement, forKey: "chromeFolderBookmark")
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        let task: Task<[ChromeProfile], Error>
        if let active = refreshTask { task = active }
        else {
            isRefreshing = true
            let root = accessURL ?? Self.standardRoot
            task = Task.detached(priority: .userInitiated) { try ProfileParser.load(root: root) }
            refreshTask = task
        }
        do {
            profiles = try await task.value
            error = profiles.isEmpty ? ProfileError.noProfiles.localizedDescription : nil
        } catch {
            // Do not offer stale profiles when their existence cannot be verified.
            profiles = []
            self.error = error.localizedDescription
        }
        refreshTask = nil
        isRefreshing = false
        return error == nil
    }

    func grantAccess() async {
        let panel = NSOpenPanel()
        panel.title = "Allow Chrome profiles"
        panel.message = "Choose the Chrome folder to read its profile names and local avatars. Your browsing history, passwords, and cookies are not read."
        panel.prompt = "Allow access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = Self.standardRoot
        guard await panel.begin() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL.resolvingSymlinksInPath() == Self.standardRoot.standardizedFileURL.resolvingSymlinksInPath() else {
            error = "Choose the Google/Chrome folder shown when the access dialog opens."
            return
        }
        if accessed { accessURL?.stopAccessingSecurityScopedResource() }
        accessURL = url
        accessed = url.startAccessingSecurityScopedResource()
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: "chromeFolderBookmark")
        } catch {
            self.error = "Folder access could not be saved. \(error.localizedDescription)"
        }
        await refresh()
    }
}

@MainActor
enum ChromeLauncher {
    static var appURL: URL? {
        let normal = URL(fileURLWithPath: "/Applications/Google Chrome.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: normal.path) { return normal }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
    }

    static func open(_ link: WebLink, profileID: String, catalog: ProfileCatalog) async throws {
        guard await catalog.refresh() else { throw ProfileError.unreadable }
        guard catalog.profiles.contains(where: { $0.id == profileID }) else { throw ProfileError.missingProfile }
        guard let app = appURL else { throw ProfileError.chromeMissing }
        let arguments = try ChromeArguments.make(profileID: profileID, link: link)
        // Chrome's singleton forwards the new invocation to the selected
        // profile. Let Chrome raise that destination window itself: asking
        // Launch Services to activate the app can raise a different Chrome
        // window after the requested tab opens.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
        let launched = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        // Launch Services can finish before Chrome's singleton has handed the
        // URL to its existing process. Showing the next picker at that point
        // lets Chrome's later activation steal its keyboard focus. Wait for the
        // destination process to receive activation before continuing the queue.
        // This is bounded so a slow browser never traps the request pipeline.
        for _ in 0..<150 {
            let forwarded = existing.isEmpty || existing.contains(where: { $0.processIdentifier == launched.processIdentifier }) || launched.isTerminated
            let destinations = existing.isEmpty ? [launched] : existing
            if forwarded && destinations.contains(where: { !$0.isTerminated && $0.isActive && $0.isFinishedLaunching }) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
