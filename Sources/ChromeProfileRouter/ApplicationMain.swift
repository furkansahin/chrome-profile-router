import AppKit
import RouterCore

@main
struct ApplicationMain {
    @MainActor
    static func main() {
        // Read-only diagnostic; normal launches run the menu-bar app.
        if CommandLine.arguments.contains("--diagnose") {
            do {
                let profiles = try ProfileParser.load(root: ProfileCatalog.standardRoot)
                for profile in profiles { print("\(profile.id)\t\(profile.name)") }
                exit(0)
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        let application = NSApplication.shared
        let delegate = AppController()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
