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

    public var description: String {
        switch self {
        case .invalidName(let name): "Invalid bottle name: '\(name)'"
        case .alreadyExists(let name): "Bottle '\(name)' already exists"
        case .notFound(let name): "Bottle '\(name)' not found"
        case .unknownTemplate(let template):
            "Unknown template '\(template)'. Valid: "
                + WindowsVersion.allCases.map(\.rawValue).joined(separator: ", ")
        }
    }
}
