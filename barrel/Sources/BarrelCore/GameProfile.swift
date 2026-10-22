import Foundation

/// How well a game runs with its profile.
public enum GameStatus: String, Codable, Sendable {
    case works, issues, broken
}

/// What one Steam game needs to run well, applied when Barrel launches it. Most games need no
/// profile: the bottle's defaults are enough. See docs/profiles.md.
public struct GameProfile: Equatable, Sendable {
    public var steamAppID: Int
    public var name: String
    public var status: GameStatus
    /// The executable that renders the game (file name only); guessed from the install folder when nil.
    public var executable: String?
    /// Direct3D backend for this game, unless the player picked one.
    public var graphics: GraphicsBackend?
    /// Wine DLL overrides for this game's executable (dll → "native", "builtin", "native,builtin", …).
    public var dllOverrides: [String: String]
    /// Passed to the game after `steam -applaunch <id>`.
    public var launchArguments: [String]
    public var notes: String?

    public init(steamAppID: Int, name: String, status: GameStatus, executable: String? = nil,
                graphics: GraphicsBackend? = nil, dllOverrides: [String: String] = [:],
                launchArguments: [String] = [], notes: String? = nil) {
        self.steamAppID = steamAppID
        self.name = name
        self.status = status
        self.executable = executable
        self.graphics = graphics
        self.dllOverrides = dllOverrides
        self.launchArguments = launchArguments
        self.notes = notes
    }
}

/// The part of a profile Barrel writes into a bottle, recorded so an unchanged profile is not
/// rewritten and a changed one can remove what it no longer sets.
struct AppliedProfile: Equatable {
    var executable: String
    var graphics: GraphicsBackend?
    var dllOverrides: [(dll: String, mode: String)]

    init(profile: GameProfile, executable: String) {
        self.executable = executable
        graphics = profile.graphics
        dllOverrides = profile.dllOverrides.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// `executable|graphics or -|dll=mode|…`
    var fingerprint: String {
        ([executable, graphics?.rawValue ?? "-"] + dllOverrides.map { "\($0.dll)=\($0.mode)" }).joined(separator: "|")
    }

    init?(fingerprint: String) {
        let parts = fingerprint.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !parts[0].isEmpty else { return nil }
        executable = parts[0]
        graphics = parts[1] == "-" ? nil : GraphicsBackend(rawValue: parts[1])
        dllOverrides = parts.dropFirst(2).compactMap { entry in
            guard let eq = entry.firstIndex(of: "=") else { return nil }
            return (String(entry[..<eq]), String(entry[entry.index(after: eq)...]))
        }
    }

    static func == (a: AppliedProfile, b: AppliedProfile) -> Bool { a.fingerprint == b.fingerprint }
}

public enum GameProfileError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case unsupportedFormat(Int)
    case missingField(String)
    case invalidValue(field: String, value: String)

    public var description: String {
        switch self {
        case .invalidJSON(let reason): "Not a valid profile: \(reason)"
        case .unsupportedFormat(let version): "Unsupported profile formatVersion \(version) (expected 1)"
        case .missingField(let field): "Missing required field '\(field)'"
        case .invalidValue(let field, let value): "Invalid \(field): '\(value)'"
        }
    }
}

public enum GameProfileParser {
    static let dllModes: Set<String> = ["native", "builtin", "native,builtin", "builtin,native", ""]

    public static func parse(_ data: Data) throws -> GameProfile {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch {
            throw GameProfileError.invalidJSON(error.localizedDescription)
        }
        guard let root = object as? [String: Any] else { throw GameProfileError.invalidJSON("expected an object") }
        guard let version = root["formatVersion"] as? Int else { throw GameProfileError.missingField("formatVersion") }
        guard version == 1 else { throw GameProfileError.unsupportedFormat(version) }
        guard let appID = root["steamAppId"] as? Int else { throw GameProfileError.missingField("steamAppId") }
        guard let name = root["name"] as? String, !name.isEmpty else { throw GameProfileError.missingField("name") }
        guard let statusText = root["status"] as? String else { throw GameProfileError.missingField("status") }
        guard let status = GameStatus(rawValue: statusText) else {
            throw GameProfileError.invalidValue(field: "status", value: statusText)
        }
        var profile = GameProfile(steamAppID: appID, name: name, status: status)

        if let executable = root["executable"] as? String {
            guard !executable.isEmpty, executable.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\")) == nil
            else { throw GameProfileError.invalidValue(field: "executable", value: executable) }
            profile.executable = executable
        }
        if let graphics = root["graphics"] as? String {
            guard let backend = GraphicsBackend(rawValue: graphics.lowercased()), backend.supportsPerApp
            else { throw GameProfileError.invalidValue(field: "graphics", value: graphics) }
            profile.graphics = backend
        }
        if let overrides = root["dllOverrides"] {
            guard let overrides = overrides as? [String: String] else {
                throw GameProfileError.invalidValue(field: "dllOverrides", value: "\(overrides)")
            }
            for (dll, mode) in overrides {
                let validName = !dll.isEmpty && dll.allSatisfy { $0.isLetter || $0.isNumber || "_.-".contains($0) }
                guard validName, dllModes.contains(mode) else {
                    throw GameProfileError.invalidValue(field: "dllOverrides", value: "\(dll)=\(mode)")
                }
            }
            profile.dllOverrides = overrides
        }
        if let arguments = root["launchArguments"] {
            guard let arguments = arguments as? [String] else {
                throw GameProfileError.invalidValue(field: "launchArguments", value: "\(arguments)")
            }
            profile.launchArguments = arguments
        }
        profile.notes = root["notes"] as? String
        return profile
    }
}

/// Profiles from several directories; the first directory to define a game wins, so a player's own
/// profiles can replace the bundled ones.
public struct GameProfileCatalog: Sendable {
    public struct Problem: Equatable, Sendable {
        public var file: String
        public var message: String
    }

    public private(set) var profiles: [Int: GameProfile] = [:]
    public private(set) var problems: [Problem] = []

    public init() {}

    public func profile(for appID: Int) -> GameProfile? { profiles[appID] }

    public static func load(directories: [URL]) -> GameProfileCatalog {
        var catalog = GameProfileCatalog()
        for directory in directories {
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { $0.hasSuffix(".json") }.sorted()
            for file in files {
                do {
                    let profile = try GameProfileParser.parse(Data(contentsOf: directory.appendingPathComponent(file)))
                    if catalog.profiles[profile.steamAppID] == nil { catalog.profiles[profile.steamAppID] = profile }
                } catch {
                    catalog.problems.append(Problem(file: file, message: "\(error)"))
                }
            }
        }
        return catalog
    }
}

/// Where a game's Direct3D backend comes from.
public enum GraphicsSource: String, Sendable {
    case player, profile, bottle
}

public struct GameGraphics: Equatable, Sendable {
    public var backend: GraphicsBackend
    public var source: GraphicsSource

    public init(backend: GraphicsBackend, source: GraphicsSource) {
        self.backend = backend
        self.source = source
    }
}
