import Foundation

public struct WorkSourceApp: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) { self.id = id; self.name = name }

    public static let defaults = [
        WorkSourceApp(id: "com.tinyspeck.slackmacgap", name: "Slack"),
        WorkSourceApp(id: "com.googlecode.iterm2", name: "iTerm")
    ]

    public static func restore(_ data: Data?) -> [WorkSourceApp] {
        // Missing means first setup/migration. An explicitly empty list means
        // the owner removed every automatic source and must stay empty.
        guard let data else { return defaults }
        guard let apps = try? JSONDecoder().decode([WorkSourceApp].self, from: data) else { return [] }
        var seen = Set<String>()
        return apps.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }
}
