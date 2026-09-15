import Foundation

public struct WebLink: Equatable, Sendable {
    public let rawValue: String
    public let hostname: String

    public init?(_ raw: String) {
        // Keep the original string for dispatch. Parsing is validation only.
        guard !raw.isEmpty, !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !raw.contains(" "), let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        rawValue = raw
        hostname = host
    }
}

public struct LinkRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let rawURL: String
    public let sourceBundleID: String?
    public let sourceName: String?
    public let sourcePID: Int32?
    public let cursorX: Double
    public let cursorY: Double

    public init(id: UUID = UUID(), rawURL: String, sourceBundleID: String? = nil, sourceName: String? = nil,
                sourcePID: Int32? = nil, cursorX: Double = 0, cursorY: Double = 0) {
        self.id = id
        self.rawURL = rawURL
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
        self.sourcePID = sourcePID
        self.cursorX = cursorX
        self.cursorY = cursorY
    }
    public var link: WebLink? { WebLink(rawURL) }
}

public enum Route: Equatable, Sendable {
    case automatic(profileID: String)
    case picker(message: String?)
    case invalid

    public var isAutomatic: Bool { if case .automatic = self { return true }; return false }
}

public enum Router {
    public static let slackBundleID = "com.tinyspeck.slackmacgap"

    public static func route(_ request: LinkRequest, workProfileID: String?, profiles: [ChromeProfile],
                             workSourceBundleIDs: Set<String> = Set(WorkSourceApp.defaults.map(\.id))) -> Route {
        guard request.link != nil else { return .invalid }
        guard let source = request.sourceBundleID, workSourceBundleIDs.contains(source) else {
            return .picker(message: nil)
        }
        guard let workProfileID, !workProfileID.isEmpty else {
            return .picker(message: "Choose a profile for this link. Set your work profile in Settings for automatic opening.")
        }
        guard profiles.contains(where: { $0.id == workProfileID }) else {
            return .picker(message: "Your work profile is unavailable. Choose a profile for this link.")
        }
        return .automatic(profileID: workProfileID)
    }
}

public struct PendingRequest: Equatable, Sendable {
    public let request: LinkRequest
    public var route: Route
    public init(request: LinkRequest, route: Route) { self.request = request; self.route = route }
}

public struct RequestQueue: Sendable {
    public private(set) var items: [PendingRequest] = []
    public init() {}
    public var first: PendingRequest? { items.first }
    public var count: Int { items.count }
    public var pickerCount: Int { items.filter { !$0.route.isAutomatic }.count }
    public mutating func append(_ item: PendingRequest) { items.append(item) }
    public mutating func removeFirst(id: UUID) {
        guard items.first?.request.id == id else { return }
        items.removeFirst()
    }
    public mutating func replaceFirstRoute(_ route: Route) {
        guard !items.isEmpty else { return }
        items[0].route = route
    }
    public mutating func cancelPickerRequests() { items.removeAll { !$0.route.isAutomatic } }
}

public enum ChromeArguments {
    public static func make(profileID: String, link: WebLink? = nil) throws -> [String] {
        guard ProfileParser.validDirectory(profileID) else { throw ProfileError.missingProfile }
        return ["--profile-directory=\(profileID)"] + (link.map { [$0.rawValue] } ?? [])
    }
}
