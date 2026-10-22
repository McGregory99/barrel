import BarrelCore
import BarrelRecipes
import Foundation
import Observation

/// Container: owns bottle state and runs every gateway call off the main actor.
@MainActor @Observable
public final class BottleListViewModel {
    public private(set) var bottles: [Bottle] = []
    public private(set) var defaultName: String?
    public private(set) var isBusy = false
    public private(set) var busyMessage: String?
    public private(set) var errorMessage: String?
    public private(set) var recipes: [RecipeSummary] = []
    /// The launcher app created most recently, so the view can reveal it in Finder.
    public private(set) var lastLauncher: URL?
    /// The bottle Steam runs in, or nil before Steam is installed.
    public private(set) var steamBottle: String?
    public private(set) var games: [GameSummary] = []
    /// A short note while a game or Steam starts; launching never blocks the window.
    public private(set) var launchMessage: String?
    public var selection: String?
    public var gateway: BottleGateway?

    public init(gateway: BottleGateway?) {
        self.gateway = gateway
    }

    public var selectedBottle: Bottle? { bottles.first { $0.name == selection } }

    public func isDefault(_ bottle: Bottle) -> Bool { bottle.name == defaultName }

    public func isAvailable(_ backend: GraphicsBackend) -> Bool { gateway?.isAvailable(backend) ?? (backend == .wined3d) }

    public func prefixURL(for name: String) -> URL? { gateway?.prefixURL(for: name) }

    public func dismissError() { errorMessage = nil }

    public func reportError(_ error: Error) { errorMessage = Self.describe(error) }

    // MARK: Use cases

    public func load() async {
        await perform(nil) { gateway in
            let list = try gateway.list()
            return (list, try gateway.defaultBottle())
        } apply: { [self] result in
            apply(bottles: result.0, defaultName: result.1)
        }
    }

    public func create(name: String, version: WindowsVersion, description: String?) async {
        await mutate("Creating \(name)…", select: name) { try $0.create(name: name, version: version, description: description) }
    }

    public func copy(_ source: String, to destination: String) async {
        await mutate("Copying \(source)…", select: destination) { try $0.copy(source, to: destination) }
    }

    public func restore(from archive: URL, as newName: String?) async {
        await mutate("Restoring \(archive.lastPathComponent)…", select: newName) {
            try $0.restore(from: archive, as: newName).name
        }
    }

    public func delete(_ name: String) async {
        await mutate("Deleting \(name)…") { try $0.delete(name) }
        if selection == name && !bottles.contains(where: { $0.name == name }) { selection = nil }
    }

    public func export(_ name: String, to archive: URL) async {
        await perform("Exporting \(name)…") { try $0.export(name, to: archive) } apply: { _ in }
    }

    public func run(_ file: URL, in name: String) async {
        await perform("Running \(file.lastPathComponent)…") { try $0.run(file.path, in: name) } apply: { _ in }
    }

    public func setGraphics(_ name: String, backend: GraphicsBackend) async {
        await mutate("Applying \(backend.rawValue)…") { try $0.setGraphics(name, backend: backend) }
    }

    public func setMSync(_ name: String, enabled: Bool) async {
        await mutate(nil) { try $0.setMSync(name, enabled: enabled) }
    }

    public func setDefault(_ name: String?) async {
        await mutate(nil) { try $0.setDefault(name) }
    }

    public func loadRecipes() async {
        await perform(nil) { try $0.recipes() } apply: { [self] in recipes = $0 }
    }

    /// Installs a recipe into `bottle`, or into a new bottle named after the recipe when nil.
    public func install(recipe: String, into bottle: String?) async {
        let name = recipes.first { $0.id == recipe }?.name ?? recipe
        await mutate("Installing \(name)… (this can take several minutes)", selectResult: true) {
            try $0.install(recipe: recipe, bottle: bottle)
        }
    }

    public func createLauncher(name: String, program: URL, in bottle: String) async {
        await perform("Creating launcher \(name)…") { gateway in
            try gateway.createLauncher(name: name, bottle: bottle, program: program.path)
        } apply: { [self] in lastLauncher = $0 }
    }

    // MARK: Steam library

    public func loadLibrary() async {
        await perform(nil) { gateway -> (String?, [GameSummary]) in
            guard let steam = try gateway.steamBottle() else { return (nil, []) }
            return (steam, try gateway.games(in: steam))
        } apply: { [self] in
            steamBottle = $0.0
            games = $0.1
        }
    }

    /// Installs Steam into its own bottle (created by the recipe), then shows the library.
    public func installSteam() async {
        await mutate("Installing Steam… (about a minute)") { try $0.install(recipe: "steam", bottle: nil) }
        await loadLibrary()
    }

    public func play(_ game: GameSummary) async {
        guard let bottle = steamBottle else { return }
        await launch("Starting \(game.name)…") { try $0.play(appID: game.appID, in: bottle) }
    }

    public func openSteam() async {
        guard let bottle = steamBottle else { return }
        await launch("Opening Steam…") { try $0.openSteam(in: bottle) }
    }

    public func setGraphics(for game: GameSummary, backend: GraphicsBackend) async {
        guard let bottle = steamBottle, let executable = game.executable else { return }
        await perform("Applying \(backend.rawValue) to \(game.name)…") { gateway in
            try gateway.setGameGraphics(bottle: bottle, executable: executable, backend: backend)
            return try gateway.games(in: bottle)
        } apply: { [self] in games = $0 }
    }

    public func setAutomaticGraphics(for game: GameSummary) async {
        guard let bottle = steamBottle, let executable = game.executable else { return }
        await perform("Resetting \(game.name)'s graphics…") { gateway in
            try gateway.clearGameGraphics(bottle: bottle, executable: executable)
            return try gateway.games(in: bottle)
        } apply: { [self] in games = $0 }
    }

    public func addToDock(_ game: GameSummary) async {
        guard let bottle = steamBottle else { return }
        await perform("Creating \(game.name).app…") { gateway in
            try gateway.createGameLauncher(appID: game.appID, name: game.name, bottle: bottle)
        } apply: { [self] in lastLauncher = $0 }
    }

    /// Starts something long-running (Steam stays open) without the busy state; errors still surface.
    private func launch(_ message: String, _ work: @escaping @Sendable (BottleGateway) throws -> Int32) async {
        guard let gateway else { return }
        launchMessage = message
        let clear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.launchMessage == message { self?.launchMessage = nil }
        }
        do {
            _ = try await Task.detached(priority: .userInitiated) { try work(gateway) }.value
        } catch {
            errorMessage = Self.describe(error)
        }
        clear.cancel()
        if launchMessage == message { launchMessage = nil }
    }

    // MARK: Plumbing

    /// Runs a mutating call, then reloads the list. A returned name (or `select`) becomes the selection.
    /// With `selectResult`, the work's returned bottle name becomes the selection.
    private func mutate<T: Sendable>(_ message: String?, select: String? = nil, selectResult: Bool = false,
                                     _ work: @escaping @Sendable (BottleGateway) throws -> T) async {
        var selected: String?
        await perform(message) { gateway in
            let result = try work(gateway)
            let list = try gateway.list()
            return (result, list, try gateway.defaultBottle())
        } apply: { [self] result in
            apply(bottles: result.1, defaultName: result.2)
            selected = select ?? (selectResult ? result.0 as? String : nil)
        }
        if let selected { selection = selected }
    }

    private func apply(bottles: [Bottle], defaultName: String?) {
        self.bottles = bottles
        self.defaultName = defaultName
        if let selection, !bottles.contains(where: { $0.name == selection }) { self.selection = nil }
    }

    private func perform<T: Sendable>(_ message: String?, _ work: @escaping @Sendable (BottleGateway) throws -> T,
                                      apply: (T) -> Void) async {
        guard let gateway else {
            errorMessage = "Barrel is not configured. Open Settings."
            return
        }
        isBusy = true
        busyMessage = message
        defer { isBusy = false; busyMessage = nil }
        do {
            let result = try await Task.detached(priority: .userInitiated) { try work(gateway) }.value
            apply(result)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case let error as BottleError: error.description
        case let error as WineRuntimeError: error.description
        case let error as RecipeError: error.description
        case let error as LauncherError: error.description
        case let error as GatewayError: error.description
        default: error.localizedDescription
        }
    }
}
