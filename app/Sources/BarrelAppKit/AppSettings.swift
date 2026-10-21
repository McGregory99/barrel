import BarrelCore
import Foundation

/// Component locations the app needs; empty strings mean "not set".
public struct AppSettings: Equatable, Sendable {
    public var wineBinary = ""
    public var dataDirectory: URL
    public var librariesDirectory = ""
    public var dxvkDirectory = ""
    public var dxmtDirectory = ""
    public var gptkDirectory = ""

    public static let defaultDataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Barrel", isDirectory: true)

    public init(dataDirectory: URL = AppSettings.defaultDataDirectory) {
        self.dataDirectory = dataDirectory
    }

    public var components: RuntimeComponents {
        func url(_ path: String) -> URL? { path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true) }
        return RuntimeComponents(libraryDirectory: url(librariesDirectory), dxvkDirectory: url(dxvkDirectory),
                                 dxmtDirectory: url(dxmtDirectory), gptkDirectory: url(gptkDirectory))
    }

    /// The configured wine binary, else `wine` from PATH, else a path that fails with a clear OS error.
    public var resolvedWineBinary: URL {
        if !wineBinary.isEmpty { return URL(fileURLWithPath: wineBinary) }
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("wine")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return URL(fileURLWithPath: "/usr/local/bin/wine")
    }
}

/// Persists `AppSettings` in UserDefaults; the CLI's BARREL_* variables seed unset values.
public struct SettingsStore {
    private let defaults: UserDefaults
    private let environment: [String: String]

    private enum Key {
        static let wine = "wineBinary", home = "dataDirectory", libs = "librariesDirectory"
        static let dxvk = "dxvkDirectory", dxmt = "dxmtDirectory", gptk = "gptkDirectory"
    }

    public init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.environment = environment
    }

    public func load() -> AppSettings {
        func value(_ key: String, _ env: String) -> String {
            defaults.string(forKey: key) ?? environment[env] ?? ""
        }
        var settings = AppSettings()
        let home = value(Key.home, "BARREL_HOME")
        if !home.isEmpty { settings.dataDirectory = URL(fileURLWithPath: home, isDirectory: true) }
        settings.wineBinary = value(Key.wine, "BARREL_WINE")
        settings.librariesDirectory = value(Key.libs, "BARREL_LIBS")
        settings.dxvkDirectory = value(Key.dxvk, "BARREL_DXVK")
        settings.dxmtDirectory = value(Key.dxmt, "BARREL_DXMT")
        settings.gptkDirectory = value(Key.gptk, "BARREL_GPTK")
        return settings
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.wineBinary, forKey: Key.wine)
        defaults.set(settings.dataDirectory.path, forKey: Key.home)
        defaults.set(settings.librariesDirectory, forKey: Key.libs)
        defaults.set(settings.dxvkDirectory, forKey: Key.dxvk)
        defaults.set(settings.dxmtDirectory, forKey: Key.dxmt)
        defaults.set(settings.gptkDirectory, forKey: Key.gptk)
    }
}
