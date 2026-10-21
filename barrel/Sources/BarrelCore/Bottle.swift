import Foundation

/// Windows version a bottle reports to applications.
/// Every bottle is a 64-bit WoW64 prefix; 32-bit programs run through WoW64,
/// so the legacy `_64` template suffix only selects the version.
public enum WindowsVersion: String, Codable, CaseIterable, Sendable {
    case win98, win2000, winxp, winvista, win7, win8, win10, win11

    public init(template: String) throws {
        let base = template.hasSuffix("_64") ? String(template.dropLast(3)) : template
        guard let version = WindowsVersion(rawValue: base) else {
            throw BottleError.unknownTemplate(template)
        }
        self = version
    }

    /// Value accepted by `winecfg -v`.
    public var winecfgName: String {
        switch self {
        case .win2000: "win2k"
        case .winvista: "vista"
        default: rawValue
        }
    }
}

public struct Bottle: Codable, Equatable, Sendable {
    public var name: String
    public var uuid: UUID
    public var windowsVersion: WindowsVersion
    public var description: String?
    public var createdAt: Date
    public var graphicsBackend: GraphicsBackend = .wined3d
    /// Mach-semaphore synchronization (CrossOver's MSync patches).
    public var msync = true

    private enum CodingKeys: String, CodingKey {
        case name, uuid, windowsVersion, description, createdAt, graphicsBackend, msync
    }

    /// Fields added after the first metadata version fall back to their defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        uuid = try container.decode(UUID.self, forKey: .uuid)
        windowsVersion = try container.decode(WindowsVersion.self, forKey: .windowsVersion)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        graphicsBackend = try container.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend) ?? .wined3d
        msync = try container.decodeIfPresent(Bool.self, forKey: .msync) ?? true
    }

    public init(
        name: String, uuid: UUID = UUID(), windowsVersion: WindowsVersion,
        description: String? = nil, createdAt: Date = Date()
    ) {
        self.name = name
        self.uuid = uuid
        self.windowsVersion = windowsVersion
        self.description = description
        self.createdAt = Self.wholeSeconds(createdAt)
    }

    /// Metadata stores ISO-8601 timestamps, which keep whole seconds only.
    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

public enum BottleError: Error, Equatable, CustomStringConvertible {
    case invalidName(String)
    case alreadyExists(String)
    case notFound(String)
    case unknownTemplate(String)
    case invalidArchive(String)
    case noDefaultBottle
    case unknownBackend(String)
    case backendUnavailable(GraphicsBackend)

    public var description: String {
        switch self {
        case .unknownBackend(let name):
            "Unknown graphics backend '\(name)'. Valid: "
                + GraphicsBackend.allCases.map(\.rawValue).joined(separator: ", ")
        case .backendUnavailable(let backend):
            "Graphics backend '\(backend.rawValue)' is not installed (see 'barrel graphics --help')"
        case .invalidArchive(let path): "'\(path)' does not contain a bottle"
        case .noDefaultBottle: "No bottle given and no default bottle set"
        case .invalidName(let name): "Invalid bottle name: '\(name)'"
        case .alreadyExists(let name): "Bottle '\(name)' already exists"
        case .notFound(let name): "Bottle '\(name)' not found"
        case .unknownTemplate(let template):
            "Unknown template '\(template)'. Valid: "
                + WindowsVersion.allCases.map(\.rawValue).joined(separator: ", ")
        }
    }
}
