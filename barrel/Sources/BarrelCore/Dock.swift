import Foundation

/// App tiles pinned in the macOS Dock.
public protocol DockTiles: Sendable {
    /// Whether a tile for the app is in the Dock.
    func contains(_ app: URL) -> Bool
    /// Adds a tile for the app at the end of the Dock's apps; does nothing if one is there.
    func add(_ app: URL, label: String) throws
    /// Removes the app's tiles; does nothing if there are none.
    func remove(_ app: URL) throws
}

public enum DockError: Error, Equatable, CustomStringConvertible {
    case unreadable
    case notSaved

    public var description: String {
        switch self {
        case .unreadable: "Could not read the Dock's apps; leaving the Dock untouched"
        case .notSaved: "Could not save the Dock's apps"
        }
    }
}

/// Where the Dock's `persistent-apps` list is kept.
public protocol DockStore: Sendable {
    /// The list, or nil when it cannot be read (so it is never overwritten blindly).
    func persistentApps() -> [Any]?
    func setPersistentApps(_ apps: [Any]) throws
}

/// The Dock's apps in a `DockStore`. Tiles are matched by file URL (trailing slash, percent-encoding
/// and symlinks ignored); other entries are kept as they are, in their order.
public struct Dock: DockTiles {
    let store: DockStore

    public init(store: DockStore) {
        self.store = store
    }

    /// The user's Dock (`com.apple.dock`), restarted after each change.
    public static let system = Dock(store: SystemDockStore())

    public func contains(_ app: URL) -> Bool {
        let path = Self.normalized(app)
        return store.persistentApps()?.contains { Self.path(of: $0) == path } ?? false
    }

    public func add(_ app: URL, label: String) throws {
        guard let apps = store.persistentApps() else { throw DockError.unreadable }
        let path = Self.normalized(app)
        guard !apps.contains(where: { Self.path(of: $0) == path }) else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true).absoluteString
        let tile: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": ["file-data": ["_CFURLString": url, "_CFURLStringType": 15], "file-label": label],
        ]
        try store.setPersistentApps(apps + [tile])
    }

    public func remove(_ app: URL) throws {
        guard let apps = store.persistentApps() else { throw DockError.unreadable }
        let path = Self.normalized(app)
        let kept = apps.filter { Self.path(of: $0) != path }
        if kept.count != apps.count { try store.setPersistentApps(kept) }
    }

    /// The normalized file path of a tile, or nil for entries that are not file tiles.
    static func path(of entry: Any) -> String? {
        guard let tileData = (entry as? [String: Any])?["tile-data"] as? [String: Any],
              let string = (tileData["file-data"] as? [String: Any])?["_CFURLString"] as? String
        else { return nil }
        let url = string.hasPrefix("/") ? URL(fileURLWithPath: string) : URL(string: string)
        guard let url, url.isFileURL else { return nil }
        return normalized(url)
    }

    static func normalized(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

/// The Dock's preferences (`com.apple.dock` `persistent-apps`); saving restarts the Dock so it shows them.
public struct SystemDockStore: DockStore {
    static var domain: CFString { "com.apple.dock" as CFString }
    static var key: CFString { "persistent-apps" as CFString }

    public init() {}

    public func persistentApps() -> [Any]? {
        CFPreferencesAppSynchronize(Self.domain)
        return CFPreferencesCopyAppValue(Self.key, Self.domain) as? [Any]
    }

    public func setPersistentApps(_ apps: [Any]) throws {
        CFPreferencesSetAppValue(Self.key, apps as CFArray, Self.domain)
        guard CFPreferencesAppSynchronize(Self.domain) else { throw DockError.notSaved }
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["Dock"]
        try killall.run()
        killall.waitUntilExit()
    }
}

/// A Dock list kept in memory, for tests; `apps` nil acts as an unreadable Dock.
public final class MemoryDockStore: DockStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Any]?
    private var writeCount = 0

    public init(apps: [Any]? = []) {
        stored = apps
    }

    public var apps: [Any] { lock.withLock { stored ?? [] } }
    /// How many times the list was saved.
    public var writes: Int { lock.withLock { writeCount } }

    public func persistentApps() -> [Any]? { lock.withLock { stored } }

    public func setPersistentApps(_ apps: [Any]) throws {
        lock.withLock { stored = apps; writeCount += 1 }
    }
}
