import Foundation

public struct ChromeProfile: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let avatarPath: String?
    public var label: String

    public init(id: String, name: String, avatarPath: String? = nil, label: String? = nil) {
        self.id = id
        self.name = name
        self.avatarPath = avatarPath
        self.label = label ?? name
    }

    public var initials: String {
        let letters = name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

public enum ProfileError: LocalizedError, Equatable {
    case unreadable
    case invalidMetadata
    case noProfiles
    case missingProfile
    case chromeMissing

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Chrome profiles aren’t accessible. Allow access to the Chrome folder in Settings, then retry."
        case .invalidMetadata: return "Chrome’s profile list couldn’t be read. Open Chrome, then retry."
        case .noProfiles: return "No Chrome profiles were found. Create a profile in Chrome, then retry."
        case .missingProfile: return "That Chrome profile is no longer available. Choose another profile."
        case .chromeMissing: return "Google Chrome couldn’t be found. Install it in Applications, then retry."
        }
    }
}

public enum ProfileParser {
    // Chrome may display an account name and local name together, for example
    // “Alex (Person 1)”. Keep the same naming/disambiguation rules.
    private static func accountName(_ entry: [String: Any]) -> String {
        for key in ["gaia_given_name", "gaia_name"] {
            if let name = entry[key] as? String, !name.isEmpty { return name }
        }
        return ""
    }

    private static func localName(_ entry: [String: Any], id: String) -> String {
        for key in ["enterprise_label", "name"] {
            if let name = entry[key] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        }
        return id
    }

    private static func displayName(id: String, entry: [String: Any], entries: [String: [String: Any]]) -> String {
        let local = localName(entry, id: id)
        let account = accountName(entry)
        guard !account.isEmpty else { return local }
        guard local.caseInsensitiveCompare(account) != .orderedSame else { return account }
        let customName = entry["is_using_default_name"] as? Bool != true || !(entry["enterprise_label"] as? String ?? "").isEmpty
        let needsDisambiguation = entries.contains { otherID, other in
            otherID != id && accountName(other) == account &&
                (other["is_using_default_name"] as? Bool == true || localName(other, id: otherID).caseInsensitiveCompare(account) == .orderedSame)
        }
        return customName || needsDisambiguation ? "\(account) (\(local))" : account
    }

    public static func validDirectory(_ name: String) -> Bool {
        name == "Default" || (name.hasPrefix("Profile ") && !name.dropFirst(8).isEmpty
            && name.dropFirst(8).allSatisfy(\.isNumber))
    }

    public static func parse(_ data: Data, root: URL, existingDirectories: Set<String>) throws -> [ChromeProfile] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = object["profile"] as? [String: Any],
              let entries = profile["info_cache"] as? [String: [String: Any]] else {
            throw ProfileError.invalidMetadata
        }
        var profiles: [ChromeProfile] = entries.compactMap { id, entry in
            guard validDirectory(id), existingDirectories.contains(id), entry["is_omitted"] as? Bool != true else { return nil }
            let name = displayName(id: id, entry: entry, entries: entries)
            var avatar: String?
            if let file = entry["gaia_picture_file_name"] as? String, !file.isEmpty,
               file == (file as NSString).lastPathComponent, file != ".", file != ".." {
                avatar = root.appendingPathComponent(id).appendingPathComponent(file).path
            }
            return ChromeProfile(id: id, name: name, avatarPath: avatar)
        }
        let counts = Dictionary(grouping: profiles, by: \.name).mapValues(\.count)
        for index in profiles.indices where (counts[profiles[index].name] ?? 0) > 1 {
            profiles[index].label = "\(profiles[index].name) · \(profiles[index].id)"
        }
        profiles.sort {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return profiles
    }

    public static func load(root: URL) throws -> [ChromeProfile] {
        let fileManager = FileManager.default
        let data: Data
        do { data = try Data(contentsOf: root.appendingPathComponent("Local State")) }
        catch { throw ProfileError.unreadable }
        let directories: [URL]
        do { directories = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) }
        catch { throw ProfileError.unreadable }
        let existing = Set(directories.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map(\.lastPathComponent))
        return try parse(data, root: root, existingDirectories: existing)
    }
}
