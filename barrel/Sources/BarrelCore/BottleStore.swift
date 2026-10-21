import Foundation

/// Persistence port for bottles and their Wine prefixes.
public protocol BottleStore {
    func prefixURL(for name: String) -> URL
    func exists(_ name: String) -> Bool
    func list() throws -> [Bottle]
    func load(_ name: String) throws -> Bottle
    func save(_ bottle: Bottle) throws
    func remove(_ name: String) throws
    func duplicate(_ source: String, to destination: String) throws
    /// Reads bottle metadata from a directory outside the store (e.g. an extracted archive).
    func readBottle(at directory: URL) throws -> Bottle
    /// Moves an external bottle directory into the store under `name`.
    func adopt(_ directory: URL, as name: String) throws
    func defaultBottleName() throws -> String?
    func setDefaultBottleName(_ name: String?) throws
}

/// Stores each bottle as `<root>/Bottles/<name>/` holding the Wine prefix
/// plus a `barrel.json` metadata file.
public struct FileBottleStore: BottleStore {
    public let root: URL
    private let fileManager = FileManager.default
    private static let metadataFile = "barrel.json"

    private var bottlesDirectory: URL { root.appendingPathComponent("Bottles") }
    private var settingsURL: URL { root.appendingPathComponent("settings.json") }

    private struct Settings: Codable {
        var defaultBottle: String?
    }

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Bottles"), withIntermediateDirectories: true)
    }

    public func prefixURL(for name: String) -> URL {
        bottlesDirectory.appendingPathComponent(name, isDirectory: true)
    }

    public func exists(_ name: String) -> Bool {
        fileManager.fileExists(atPath: metadataURL(for: name).path)
    }

    public func list() throws -> [Bottle] {
        try fileManager.contentsOfDirectory(atPath: bottlesDirectory.path)
            .filter(exists)
            .map(load)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func load(_ name: String) throws -> Bottle {
        guard exists(name) else { throw BottleError.notFound(name) }
        return try decoder.decode(Bottle.self, from: Data(contentsOf: metadataURL(for: name)))
    }

    public func save(_ bottle: Bottle) throws {
        try fileManager.createDirectory(
            at: prefixURL(for: bottle.name), withIntermediateDirectories: true)
        try encoder.encode(bottle).write(to: metadataURL(for: bottle.name), options: .atomic)
    }

    public func remove(_ name: String) throws {
        let url = prefixURL(for: name)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func duplicate(_ source: String, to destination: String) throws {
        try fileManager.copyItem(at: prefixURL(for: source), to: prefixURL(for: destination))
    }

    public func readBottle(at directory: URL) throws -> Bottle {
        let url = directory.appendingPathComponent(Self.metadataFile)
        guard fileManager.fileExists(atPath: url.path) else {
            throw BottleError.invalidArchive(directory.path)
        }
        return try decoder.decode(Bottle.self, from: Data(contentsOf: url))
    }

    public func adopt(_ directory: URL, as name: String) throws {
        try fileManager.moveItem(at: directory, to: prefixURL(for: name))
    }

    public func defaultBottleName() throws -> String? {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return nil }
        return try decoder.decode(Settings.self, from: Data(contentsOf: settingsURL)).defaultBottle
    }

    public func setDefaultBottleName(_ name: String?) throws {
        try encoder.encode(Settings(defaultBottle: name)).write(to: settingsURL, options: .atomic)
    }

    private func metadataURL(for name: String) -> URL {
        prefixURL(for: name).appendingPathComponent(Self.metadataFile)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
