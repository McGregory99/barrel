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
    /// Games in the player's Steam library that are not installed, shown greyed out.
    public private(set) var uninstalledGames: [GameSummary] = []
    /// A short note while a game or Steam starts; launching never blocks the window.
    public private(set) var launchMessage: String?
    /// True from clicking Open Steam until Steam's window is on screen (or it fails or times out).
    public private(set) var isOpeningSteam = false
    public var selection: String?
    public var gateway: BottleGateway?
    private let windows: WindowSource
    private let steamPollInterval: Duration
    private let steamTimeout: TimeInterval
    /// How the steam.exe started by the current Open Steam ended, once it has.
    private var steamLaunch: Result<Int32, Error>?
    private var steamAttempt = 0

    public init(gateway: BottleGateway?, windows: WindowSource = SystemWindowSource(),
                steamPollInterval: Duration = .seconds(1), steamTimeout: TimeInterval = 180) {
        self.gateway = gateway
        self.windows = windows
        self.steamPollInterval = steamPollInterval
        self.steamTimeout = steamTimeout
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

    /// Reads the installed games and the rest of the Steam library (Sync Library runs this again).
    public func loadLibrary() async {
        await perform(nil) { gateway -> (String?, [GameSummary], [GameSummary]) in
            guard let steam = try gateway.steamBottle() else { return (nil, [], []) }
            return (steam, try gateway.games(in: steam), try gateway.uninstalledGames(in: steam))
        } apply: { [self] in
            steamBottle = $0.0
            games = $0.1
            uninstalledGames = $0.2
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

    /// Opens Steam's install dialog for a game; once Steam finishes, Sync Library shows it as installed.
    public func installGame(_ game: GameSummary) async {
        guard let bottle = steamBottle else { return }
        await launch("Opening Steam to install \(game.name)…") { try $0.installGame(appID: game.appID, in: bottle) }
    }

    /// Starts Steam and stays in the opening state until its window is on screen: under Wine
    /// that can take most of a minute. Steam keeps running afterwards, so its exit is watched, not awaited.
    public func openSteam() async {
        guard let bottle = steamBottle, let gateway, !isOpeningSteam else { return }
        let message = "Opening Steam… (this can take a minute)"
        isOpeningSteam = true
        launchMessage = message
        defer {
            isOpeningSteam = false
            if launchMessage == message { launchMessage = nil }
        }
        let watch = SteamWindowWatch(before: windows.onScreenWindows(), startedAt: Date(), timeout: steamTimeout)
        steamAttempt += 1
        let attempt = steamAttempt
        steamLaunch = nil
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try gateway.openSteam(in: bottle) }
            }.value
            guard let self, steamAttempt == attempt else { return }
            steamLaunch = result
            // Errors after the window showed still surface; while opening, the watch reports them.
            if !isOpeningSteam, case .failure(let error) = result { errorMessage = Self.describe(error) }
        }
        while true {
            let launch: SteamWindowWatch.Launch
            switch steamLaunch {
            case .failure(let error):
                errorMessage = Self.describe(error)
                return
            case .success(let code): launch = .exited(code)
            case nil: launch = .running
            }
            switch watch.state(windows: windows.onScreenWindows(), now: Date(), launch: launch) {
            case .waiting:
                try? await Task.sleep(for: steamPollInterval)
            case .ready:
                return
            case .failed(let code):
                errorMessage = "Steam closed before its window appeared (exit code \(code))."
                return
            case .timedOut:
                errorMessage = "Steam is taking longer than usual to open. It may still appear; if it does not, click Open Steam again."
                return
            }
        }
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

    /// Creates the game's Mac app and pins it in the Dock, then reloads the games so its card shows "In Dock".
    public func addToDock(_ game: GameSummary) async {
        await changeDock(game, to: true, "Adding \(game.name) to the Dock…") { gateway, bottle in
            try gateway.createGameLauncher(appID: game.appID, name: game.name, bottle: bottle)
        }
    }

    /// Takes the game out of the Dock and moves its Mac app to the Trash, then reloads the games so its
    /// card offers Add to Dock again.
    public func removeFromDock(_ game: GameSummary) async {
        await changeDock(game, to: false, "Removing \(game.name) from the Dock…") { gateway, _ in
            try gateway.removeGameLauncher(name: game.name)
            return nil
        }
    }

    /// Runs a Dock change, then reloads the games even if the change failed part way (say, after the
    /// app was trashed), so the card shows what happened. If only the reload fails, the card is set
    /// from the change. The first error is shown.
    private func changeDock(_ game: GameSummary, to inDock: Bool, _ message: String,
                            _ change: @escaping @Sendable (BottleGateway, String) throws -> URL?) async {
        guard let bottle = steamBottle else { return }
        await perform(message) { gateway in
            var app: URL?, changed = false, error: Error?, reloaded: [GameSummary]?
            do { app = try change(gateway, bottle); changed = true } catch let failure { error = failure }
            do { reloaded = try gateway.games(in: bottle) } catch let failure { error = error ?? failure }
            return DockChange(app: app, changed: changed, reloaded: reloaded, error: error)
        } apply: { [self] result in
            if let app = result.app { lastLauncher = app }
            if let reloaded = result.reloaded {
                games = reloaded
            } else if result.changed {
                for i in games.indices where games[i].appID == game.appID { games[i].isInDock = inDock }
            }
            if let error = result.error { errorMessage = Self.describe(error) }
        }
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
        case let error as DockError: error.description
        case let error as GatewayError: error.description
        default: error.localizedDescription
        }
    }
}

/// What an Add to Dock or Remove from Dock did: the app made, the reloaded games, and the first error.
private struct DockChange: Sendable {
    var app: URL?
    var changed: Bool
    var reloaded: [GameSummary]?
    var error: Error?
}
