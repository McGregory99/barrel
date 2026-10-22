import BarrelCore
import BarrelRecipes
import Foundation

public enum GatewayError: Error, Equatable, CustomStringConvertible {
    case launchersNeedBarrelApp

    public var description: String {
        switch self {
        case .launchersNeedBarrelApp:
            "Launchers need the barrel command-line tool that ships inside Barrel.app; run the packaged app."
        }
    }
}

/// What the app shows for an install recipe.
public struct RecipeSummary: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

/// Port the view models use to reach bottle management. Calls block (Wine), so
/// callers must invoke them off the main actor.
public protocol BottleGateway: Sendable {
    func list() throws -> [Bottle]
    func defaultBottle() throws -> String?
    func isAvailable(_ backend: GraphicsBackend) -> Bool
    func prefixURL(for name: String) -> URL
    func create(name: String, version: WindowsVersion, description: String?) throws -> Bottle
    func copy(_ source: String, to destination: String) throws -> Bottle
    func delete(_ name: String) throws
    func export(_ name: String, to archive: URL) throws
    func restore(from archive: URL, as newName: String?) throws -> Bottle
    func run(_ path: String, in bottle: String) throws -> Int32
    func setGraphics(_ name: String, backend: GraphicsBackend) throws
    func setMSync(_ name: String, enabled: Bool) throws
    func setDefault(_ name: String?) throws
    func recipes() throws -> [RecipeSummary]
    /// Installs a recipe and its dependencies; nil `bottle` uses (and creates) one named after the recipe.
    /// Returns the bottle used.
    func install(recipe: String, bottle: String?) throws -> String
    /// Creates a macOS app that opens `program` in `bottle`; returns its URL.
    func createLauncher(name: String, bottle: String, program: String) throws -> URL
}

/// Adapter from the gateway port to `BottleService`.
public final class BarrelCoreGateway: BottleGateway, @unchecked Sendable {
    private let service: BottleService
    private let store: BottleStore
    private let components: RuntimeComponents
    private let recipeDirectories: [URL]
    private let downloadsDirectory: URL
    private let launcherEnvironment: [String: String]
    private let barrelExecutable: URL?
    private let launchers: LauncherInstaller

    public init(store: BottleStore, wineBinary: URL, components: RuntimeComponents,
                recipeDirectories: [URL] = [], downloadsDirectory: URL,
                launcherEnvironment: [String: String] = [:], barrelExecutable: URL? = nil,
                launchersDirectory: URL = BarrelCoreGateway.defaultLaunchersDirectory) {
        self.store = store
        self.components = components
        self.recipeDirectories = recipeDirectories
        self.downloadsDirectory = downloadsDirectory
        self.launcherEnvironment = launcherEnvironment
        self.barrelExecutable = barrelExecutable
        self.launchers = LauncherInstaller(directory: launchersDirectory)
        self.service = BottleService(store: store, runtime: ProcessWineRuntime(wineBinary: wineBinary),
                                     components: components)
    }

    public static let defaultLaunchersDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/Barrel", isDirectory: true)

    /// Builds the production gateway from user settings, creating the data directory if needed.
    /// Launchers call the `barrel` tool bundled next to the app's executable.
    public convenience init(settings: AppSettings,
                            barrelExecutable: URL? = Bundle.main.url(forAuxiliaryExecutable: "barrel"),
                            launchersDirectory: URL = BarrelCoreGateway.defaultLaunchersDirectory) throws {
        // Launchers start outside the app, so they carry the settings as BARREL_* variables.
        var environment = ["BARREL_HOME": settings.dataDirectory.path,
                           "BARREL_WINE": settings.resolvedWineBinary.path]
        for (key, value) in [("BARREL_LIBS", settings.librariesDirectory), ("BARREL_DXVK", settings.dxvkDirectory),
                             ("BARREL_DXMT", settings.dxmtDirectory), ("BARREL_GPTK", settings.gptkDirectory)]
        where !value.isEmpty {
            environment[key] = value
        }
        try self.init(store: FileBottleStore(root: settings.dataDirectory),
                      wineBinary: settings.resolvedWineBinary, components: settings.components,
                      recipeDirectories: settings.recipeDirectories,
                      downloadsDirectory: settings.dataDirectory.appendingPathComponent("Downloads", isDirectory: true),
                      launcherEnvironment: environment, barrelExecutable: barrelExecutable,
                      launchersDirectory: launchersDirectory)
    }

    public func list() throws -> [Bottle] { try service.list() }
    public func defaultBottle() throws -> String? { try service.defaultBottle() }
    public func isAvailable(_ backend: GraphicsBackend) -> Bool { components.isAvailable(backend) }
    public func prefixURL(for name: String) -> URL { store.prefixURL(for: name) }
    public func create(name: String, version: WindowsVersion, description: String?) throws -> Bottle {
        try service.create(name: name, version: version, description: description)
    }
    public func copy(_ source: String, to destination: String) throws -> Bottle {
        try service.copy(source, to: destination)
    }
    public func delete(_ name: String) throws { try service.delete(name) }
    public func export(_ name: String, to archive: URL) throws { try service.export(name, to: archive) }
    public func restore(from archive: URL, as newName: String?) throws -> Bottle {
        try service.restore(from: archive, as: newName)
    }
    public func run(_ path: String, in bottle: String) throws -> Int32 {
        try service.run(path, arguments: [], bottle: bottle)
    }
    public func setGraphics(_ name: String, backend: GraphicsBackend) throws {
        try service.setGraphics(name, backend: backend)
    }
    public func setMSync(_ name: String, enabled: Bool) throws { try service.setMSync(name, enabled: enabled) }
    public func setDefault(_ name: String?) throws { try service.setDefault(name) }

    public func recipes() throws -> [RecipeSummary] {
        RecipeCatalog.load(directories: recipeDirectories).visible
            .map { RecipeSummary(id: $0.id, name: $0.name, description: $0.description) }
    }

    public func install(recipe: String, bottle: String?) throws -> String {
        let executor = RecipeExecutor(host: BottleServiceHost(service: service, store: store),
                                      downloads: DownloadCache(directory: downloadsDirectory,
                                                               downloader: URLSessionDownloader()))
        return try executor.install(recipe, catalog: RecipeCatalog.load(directories: recipeDirectories), bottle: bottle)
    }

    public func createLauncher(name: String, bottle: String, program: String) throws -> URL {
        guard let barrelExecutable else { throw GatewayError.launchersNeedBarrelApp }
        let spec = LauncherSpec(name: name, bottle: bottle, program: program, environment: launcherEnvironment,
                                barrelExecutable: barrelExecutable)
        let icon = try? IconConverter.icns(fromExecutable: URL(fileURLWithPath: program))
        return try launchers.install(spec, icon: icon)
    }
}
