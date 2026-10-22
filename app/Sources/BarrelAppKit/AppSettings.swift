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
    /// Extra recipe folder, e.g. the repository's `recipes/`; `<data>/Recipes` is always read.
    public var recipesDirectory = ""
    /// Extra game-profile folder (Barrel.app's bundled profiles); `<data>/Profiles` is read first.
    public var profilesDirectory = ""

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

    public var recipeDirectories: [URL] {
        var directories = [dataDirectory.appendingPathComponent("Recipes", isDirectory: true)]
        if !recipesDirectory.isEmpty { directories.insert(URL(fileURLWithPath: recipesDirectory, isDirectory: true), at: 0) }
        return directories
    }

    public var profileDirectories: [URL] {
        var directories = [dataDirectory.appendingPathComponent("Profiles", isDirectory: true)]
        if !profilesDirectory.isEmpty { directories.append(URL(fileURLWithPath: profilesDirectory, isDirectory: true)) }
        return directories
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

/// Persists `AppSettings` in UserDefaults. Unset (missing or empty) values come from the CLI's
/// BARREL_* variables, then from the runtime bundled in Barrel.app (`Resources/runtime`).
public struct SettingsStore {
    private let defaults: UserDefaults
    private let environment: [String: String]
    private let bundleResources: URL?

    /// The app bundle's Resources folder when it ships a runtime, else nil (e.g. `swift run`).
    public static var bundledResources: URL? {
        guard let resources = Bundle.main.resourceURL,
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("runtime").path)
        else { return nil }
        return resources
    }

    private enum Key {
        static let wine = "wineBinary", home = "dataDirectory", libs = "librariesDirectory"
        static let dxvk = "dxvkDirectory", dxmt = "dxmtDirectory", gptk = "gptkDirectory"
        static let recipes = "recipesDirectory", profiles = "profilesDirectory"
    }

    public init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment,
                bundleResources: URL? = SettingsStore.bundledResources) {
        self.defaults = defaults
        self.environment = environment
        self.bundleResources = bundleResources
    }

    public func load() -> AppSettings {
        func value(_ key: String, _ env: String, bundled: String? = nil) -> String {
            let candidates = [defaults.string(forKey: key), environment[env],
                              bundled.flatMap { path in bundleResources.map { $0.appendingPathComponent(path).path } }]
            return candidates.compactMap { $0 }.first { !$0.isEmpty } ?? ""
        }
        var settings = AppSettings()
        let home = value(Key.home, "BARREL_HOME")
        if !home.isEmpty { settings.dataDirectory = URL(fileURLWithPath: home, isDirectory: true) }
        settings.wineBinary = value(Key.wine, "BARREL_WINE", bundled: "runtime/wine/bin/wine")
        settings.librariesDirectory = value(Key.libs, "BARREL_LIBS", bundled: "runtime/deps/lib")
        settings.dxvkDirectory = value(Key.dxvk, "BARREL_DXVK", bundled: "runtime/dxvk")
        settings.dxmtDirectory = value(Key.dxmt, "BARREL_DXMT", bundled: "runtime/dxmt")
        settings.gptkDirectory = value(Key.gptk, "BARREL_GPTK")
        settings.recipesDirectory = value(Key.recipes, "BARREL_RECIPES", bundled: "recipes")
        settings.profilesDirectory = value(Key.profiles, "BARREL_PROFILES", bundled: "profiles")
        return settings
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.wineBinary, forKey: Key.wine)
        defaults.set(settings.dataDirectory.path, forKey: Key.home)
        defaults.set(settings.librariesDirectory, forKey: Key.libs)
        defaults.set(settings.dxvkDirectory, forKey: Key.dxvk)
        defaults.set(settings.dxmtDirectory, forKey: Key.dxmt)
        defaults.set(settings.gptkDirectory, forKey: Key.gptk)
        defaults.set(settings.recipesDirectory, forKey: Key.recipes)
        defaults.set(settings.profilesDirectory, forKey: Key.profiles)
    }
}
