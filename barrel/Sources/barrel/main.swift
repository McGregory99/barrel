import ArgumentParser
import BarrelCore
import BarrelRecipes
import Foundation

struct Barrel: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Play Windows Steam games on macOS, and manage the Wine bottles behind them.",
        discussion: """
            Environment:
              BARREL_HOME  Data directory (default: ~/Library/Application Support/Barrel)
              BARREL_WINE  Path to the wine binary (default: Barrel.app's runtime, else 'wine' in PATH)
              BARREL_LIBS  Directory with native libraries such as libMoltenVK.dylib
              BARREL_DXVK  DXVK build directory (x64/, x32/)
              BARREL_DXMT  DXMT install directory (system32/, syswow64/, x86_64-unix/, …)
              (BARREL_LIBS/DXVK/DXMT also default to Barrel.app's runtime when run from the app)
              BARREL_GPTK  Your Apple Game Porting Toolkit directory (wine/, external/)
              BARREL_LAUNCHERS  Where 'barrel launcher' puts apps (default: ~/Applications/Barrel)
            Game profiles are read from $BARREL_HOME/Profiles, then Barrel.app's bundled profiles.
            """,
        subcommands: [Games.self, Play.self, Create.self, List.self, Info.self, Copy.self, Delete.self, Default.self, Templates.self,
                      Export.self, Restore.self, Run.self, Graphics.self, MSync.self,
                      Recipes.self, Install.self, Launcher.self]
    )
}

struct Environment {
    static func service() throws -> BottleService {
        BottleService(store: try FileBottleStore(root: home()), runtime: ProcessWineRuntime(wineBinary: try wine()),
                      components: components())
    }

    /// `Resources/<name>` when this binary runs from Barrel.app (`Contents/MacOS/barrel`).
    static func bundledResource(_ name: String) -> URL? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let resource = executable.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(name)", isDirectory: true)
        return FileManager.default.fileExists(atPath: resource.path) ? resource : nil
    }

    static var bundledRuntime: URL? { bundledResource("runtime") }

    /// BARREL_* variables win; otherwise the runtime bundled with Barrel.app is used.
    static func components() -> RuntimeComponents {
        let env = ProcessInfo.processInfo.environment
        func directory(_ key: String, bundled: String? = nil) -> URL? {
            if let path = env[key] { return URL(fileURLWithPath: path, isDirectory: true) }
            return bundled.flatMap { path in bundledRuntime?.appendingPathComponent(path, isDirectory: true) }
        }
        return RuntimeComponents(libraryDirectory: directory("BARREL_LIBS", bundled: "deps/lib"),
                                 dxvkDirectory: directory("BARREL_DXVK", bundled: "dxvk"),
                                 dxmtDirectory: directory("BARREL_DXMT", bundled: "dxmt"),
                                 gptkDirectory: directory("BARREL_GPTK"))
    }

    static func home() -> URL {
        if let path = ProcessInfo.processInfo.environment["BARREL_HOME"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Barrel", isDirectory: true)
    }

    static func wine() throws -> URL {
        if let path = ProcessInfo.processInfo.environment["BARREL_WINE"] {
            return URL(fileURLWithPath: path)
        }
        if let bundled = bundledRuntime?.appendingPathComponent("wine/bin/wine"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("wine")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw ValidationError("wine not found; set BARREL_WINE to your wine binary")
    }
}

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a new bottle.")

    @Argument(help: "Bottle name.") var name: String
    @Option(help: "Windows version template (see 'barrel templates').") var template = "win10"
    @Option(help: "Free-form description.") var description: String?

    func run() throws {
        let version = try WindowsVersion(template: template)
        let bottle = try Environment.service().create(name: name, version: version, description: description)
        print("Created bottle '\(bottle.name)' (\(bottle.windowsVersion.rawValue))")
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List bottles.")

    func run() throws {
        let service = try Environment.service()
        let defaultName = try service.defaultBottle()
        for bottle in try service.list() {
            let marker = bottle.name == defaultName ? "*" : " "
            print("\(marker) \(bottle.name)\t\(bottle.windowsVersion.rawValue)\t\(bottle.description ?? "")")
        }
    }
}

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show a bottle's metadata and location.")

    @Argument var name: String

    func run() throws {
        let bottle = try Environment.service().info(name)
        let prefix = try FileBottleStore(root: Environment.home()).prefixURL(for: name)
        print("""
            name:        \(bottle.name)
            uuid:        \(bottle.uuid)
            windows:     \(bottle.windowsVersion.rawValue)
            description: \(bottle.description ?? "-")
            created:     \(bottle.createdAt.ISO8601Format())
            graphics:    \(bottle.graphicsBackend.rawValue)
            msync:       \(bottle.msync ? "on" : "off")
            per-app:     \(bottle.appGraphics.isEmpty ? "-" : bottle.appGraphics.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.rawValue)" }.joined(separator: ", "))
            prefix:      \(prefix.path)
            """)
    }
}

struct Copy: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Copy a bottle.")

    @Argument var source: String
    @Argument var destination: String

    func run() throws {
        try Environment.service().copy(source, to: destination)
        print("Copied '\(source)' to '\(destination)'")
    }
}

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete a bottle and everything installed in it.")

    @Argument var name: String
    @Flag(help: "Skip the confirmation prompt.") var force = false

    func run() throws {
        if !force {
            print("Delete bottle '\(name)' and all its contents? [y/N] ", terminator: "")
            guard readLine()?.lowercased() == "y" else { throw ExitCode.failure }
        }
        try Environment.service().delete(name)
        print("Deleted '\(name)'")
    }
}

struct Default: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show, set or unset the default bottle.")

    @Argument var name: String?
    @Flag(help: "Unset the default bottle.") var unset = false

    func run() throws {
        let service = try Environment.service()
        if unset {
            try service.setDefault(nil)
        } else if let name {
            try service.setDefault(name)
        } else {
            print(try service.defaultBottle() ?? "(none)")
        }
    }
}

struct Templates: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List bottle templates.")

    func run() {
        WindowsVersion.allCases.forEach { print($0.rawValue) }
    }
}

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Export a bottle to a .tar.gz archive.")

    @Argument var name: String
    @Argument(help: "Archive path to write.") var archive: String

    func run() throws {
        try Environment.service().export(name, to: URL(fileURLWithPath: archive))
        print("Exported '\(name)' to \(archive)")
    }
}

struct Restore: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Restore a bottle from an exported archive.")

    @Argument(help: "Archive created by 'barrel export'.") var archive: String
    @Option(name: .customLong("as"), help: "Restore under a new name (gets a new identity).") var newName: String?

    func run() throws {
        let bottle = try Environment.service().restore(from: URL(fileURLWithPath: archive), as: newName)
        print("Restored bottle '\(bottle.name)'")
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run a Windows program or open a document using Windows file associations.")

    @Option(help: "Bottle to use (default: the default bottle).") var bottle: String?
    @Argument(help: "Program or document path.") var path: String
    @Argument(parsing: .captureForPassthrough, help: "Arguments passed to the program.") var arguments: [String] = []

    func run() throws {
        let status = try Environment.service().run(path, arguments: arguments, bottle: bottle)
        if status != 0 { throw ExitCode(status) }
    }
}

struct Graphics: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show or set a bottle's Direct3D backend, for the whole bottle or one executable.",
        discussion: """
            Backends: wined3d (built in), dxvk (needs BARREL_DXVK and libMoltenVK in BARREL_LIBS),
            dxmt (needs BARREL_DXMT), d3dmetal (needs BARREL_GPTK pointing to your own copy of
            Apple's Game Porting Toolkit; it is not redistributable).
            --app overrides the backend for one executable file name (wined3d, dxvk or dxmt),
            e.g. keep Steam's steamwebhelper.exe on wined3d in a DXVK bottle.
            """)

    @Argument var name: String
    @Argument(help: "wined3d, dxvk, dxmt or d3dmetal.") var backend: String?
    @Option(help: "Executable file name to override, e.g. Game.exe.") var app: String?

    func run() throws {
        let service = try Environment.service()
        guard let backend else {
            let bottle = try service.info(name)
            print(bottle.graphicsBackend.rawValue)
            for (executable, backend) in bottle.appGraphics.sorted(by: { $0.key < $1.key }) {
                print("  \(executable): \(backend.rawValue)")
            }
            return
        }
        let selected = try GraphicsBackend(name: backend)
        if let app {
            try service.setAppGraphics(name, executable: app, backend: selected)
            print("'\(app)' in bottle '\(name)' now uses \(selected.rawValue)")
        } else {
            try service.setGraphics(name, backend: selected)
            print("Bottle '\(name)' now uses \(selected.rawValue)")
        }
    }
}

struct MSync: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "msync", abstract: "Enable or disable MSync (faster synchronization) for a bottle.")

    @Argument var name: String
    @Argument(help: "on or off.") var state: String

    func run() throws {
        guard ["on", "off"].contains(state) else { throw ValidationError("state must be 'on' or 'off'") }
        try Environment.service().setMSync(name, enabled: state == "on")
        print("MSync \(state) for '\(name)'")
    }
}

extension Environment {
    static func catalog(extra: String?) -> RecipeCatalog {
        var directories = [home().appendingPathComponent("Recipes", isDirectory: true)]
        if let extra { directories.insert(URL(fileURLWithPath: extra, isDirectory: true), at: 0) }
        // Barrel.app's recipes come last so the user's own recipes with the same id win.
        if let bundled = bundledResource("recipes") { directories.append(bundled) }
        return RecipeCatalog.load(directories: directories)
    }
}

extension Environment {
    /// BARREL_* variables a launcher exports, since apps opened from Finder lack the shell environment.
    static func launcherEnvironment() throws -> [String: String] {
        var environment = ["BARREL_HOME": home().path, "BARREL_WINE": try wine().path]
        for key in ["BARREL_LIBS", "BARREL_DXVK", "BARREL_DXMT", "BARREL_GPTK"] {
            if let value = ProcessInfo.processInfo.environment[key] { environment[key] = value }
        }
        return environment
    }

    static func profiles(extra: String?) -> GameProfileCatalog {
        var directories = [home().appendingPathComponent("Profiles", isDirectory: true)]
        if let extra { directories.insert(URL(fileURLWithPath: extra, isDirectory: true), at: 0) }
        if let bundled = bundledResource("profiles") { directories.append(bundled) }
        let catalog = GameProfileCatalog.load(directories: directories)
        for problem in catalog.problems {
            FileHandle.standardError.write(Data("warning: \(problem.file): \(problem.message)\n".utf8))
        }
        return catalog
    }

    /// An installed game by Steam app id, exact name or unambiguous name prefix (case-insensitive).
    static func game(_ query: String, bottle: String) throws -> SteamGame {
        let prefix = try FileBottleStore(root: home()).prefixURL(for: bottle)
        _ = try service().info(bottle)
        let games = SteamLibrary.installedGames(prefix: prefix)
        if let id = Int(query), let game = games.first(where: { $0.appID == id }) { return game }
        let lower = query.lowercased()
        if let exact = games.first(where: { $0.name.lowercased() == lower }) { return exact }
        let matches = games.filter { $0.name.lowercased().hasPrefix(lower) }
        guard matches.count == 1 else {
            let hint = matches.isEmpty ? "no installed game matches" : "several games match: "
                + matches.map(\.name).joined(separator: ", ")
            throw ValidationError("'\(query)': \(hint) (see 'barrel games --bottle \(bottle)')")
        }
        return matches[0]
    }
}

struct Games: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the Steam games installed in a bottle, with their graphics and profile.",
        discussion: """
            Columns: Steam app id, name, Direct3D backend and who chose it (you, the game's profile or
            the bottle), and the profile status (works, issues, broken) or 'no profile'.
            """)

    @Option(help: "Bottle with Steam (default: 'steam').") var bottle = "steam"
    @Option(help: "Extra game profile directory.") var profilesDir: String?

    func run() throws {
        let service = try Environment.service()
        _ = try service.info(bottle)
        let prefix = try FileBottleStore(root: Environment.home()).prefixURL(for: bottle)
        let profiles = Environment.profiles(extra: profilesDir)
        for game in SteamLibrary.installedGames(prefix: prefix) {
            let profile = profiles.profile(for: game.appID)
            let executable = profile?.executable ?? SteamLibrary.mainExecutable(of: game)?.lastPathComponent
            let graphics = try service.gameGraphics(bottle: bottle, executable: executable, profile: profile)
            let status = profile.map { "profile: \($0.status.rawValue)" } ?? "no profile"
            print("\(game.appID)\t\(game.name)\t\(graphics.backend.rawValue) (\(graphics.source.rawValue))\t\(status)")
        }
    }
}

struct Play: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Play a Steam game, applying its profile first.",
        discussion: """
            Starts the bottle's Steam client with '-applaunch <id>'; install Steam first with 'barrel install steam'. Extra arguments after '--' go to the game.
            """)

    @Option(help: "Bottle with Steam (default: 'steam').") var bottle = "steam"
    @Option(help: "Extra game profile directory.") var profilesDir: String?
    @Argument(help: "Steam app id or game name (see 'barrel games').") var game: String
    @Argument(parsing: .postTerminator, help: "Arguments passed to the game, after '--'.") var arguments: [String] = []

    func run() throws {
        let found = try Environment.game(game, bottle: bottle)
        let profile = Environment.profiles(extra: profilesDir).profile(for: found.appID)
        let status = try Environment.service().play(found, profile: profile, bottle: bottle, arguments: arguments)
        if status != 0 { throw ExitCode(status) }
    }
}

struct Recipes: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List available install recipes.")

    @Option(help: "Extra recipe directory (also reads $BARREL_HOME/Recipes and Barrel.app's recipes).") var recipesDir: String?
    @Flag(help: "Also list hidden recipes (building blocks such as runtimes).") var all = false

    func run() throws {
        let catalog = Environment.catalog(extra: recipesDir)
        for recipe in all ? catalog.sorted : catalog.visible { print("\(recipe.id)\t\(recipe.name)") }
        for problem in catalog.problems {
            FileHandle.standardError.write(Data("warning: \(problem.file): \(problem.message)\n".utf8))
        }
    }
}

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install a recipe (and its dependencies) into a bottle.",
        discussion: "Without --bottle, a bottle named after the recipe is used and created if missing.")

    @Argument(help: "Recipe id (see 'barrel recipes').") var recipe: String
    @Option(help: "Bottle to install into.") var bottle: String?
    @Option(help: "Extra recipe directory (also reads $BARREL_HOME/Recipes and Barrel.app's recipes).") var recipesDir: String?

    func run() throws {
        let catalog = Environment.catalog(extra: recipesDir)
        let home = Environment.home()
        let store = try FileBottleStore(root: home)
        let service = BottleService(store: store, runtime: ProcessWineRuntime(wineBinary: try Environment.wine()),
                                    components: Environment.components())
        let cache = DownloadCache(directory: home.appendingPathComponent("Downloads", isDirectory: true),
                                  downloader: URLSessionDownloader())
        let executor = RecipeExecutor(host: BottleServiceHost(service: service, store: store), downloads: cache,
                                      log: { print($0) })
        let name = try executor.install(recipe, catalog: catalog, bottle: bottle)
        print("Installed '\(recipe)' into bottle '\(name)'")
    }
}

struct Launcher: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create, list or remove macOS apps that open a Windows program in a bottle.",
        subcommands: [CreateLauncher.self, GameLauncher.self, ListLaunchers.self, RemoveLauncher.self])

    static func installer() -> LauncherInstaller {
        let directory = ProcessInfo.processInfo.environment["BARREL_LAUNCHERS"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Barrel")
        return LauncherInstaller(directory: directory)
    }
}

struct CreateLauncher: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a launcher app.",
        discussion: """
            The launcher runs 'barrel run --bottle <bottle> <program> [arguments]' with the
            BARREL_* variables of the current shell, so it also works when opened from Finder.
            Example (a Steam game): barrel launcher create steam ".../Steam/steam.exe" --name Stonewards
              --icon-from ".../steamapps/common/Stonewards/Stonewards.exe" -- -applaunch 4502710
            """)

    @Argument(help: "Bottle name.") var bottle: String
    @Argument(help: "Program or document path (Unix path).") var program: String
    @Option(help: "App name (default: the program's file name without extension).") var name: String?
    @Option(help: "Windows executable to take the icon from (default: the program).") var iconFrom: String?
    @Argument(parsing: .postTerminator, help: "Arguments passed to the program, after '--'.") var arguments: [String] = []

    func run() throws {
        _ = try Environment.service().info(bottle)
        let programURL = URL(fileURLWithPath: program)
        let appName = name ?? programURL.deletingPathExtension().lastPathComponent
        guard let barrel = Bundle.main.executableURL else { throw ValidationError("cannot locate the barrel binary") }

        let spec = LauncherSpec(name: appName, bottle: bottle, program: programURL.path, arguments: arguments,
                                environment: try Environment.launcherEnvironment(),
                                barrelExecutable: barrel.resolvingSymlinksInPath())
        let app = try Launcher.installer().install(spec, icon: icon(from: iconFrom ?? programURL.path))
        print("Created \(app.path)")
    }

    private func icon(from path: String) -> Data? {
        do {
            return try IconConverter.icns(fromExecutable: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("warning: no icon from \(path): \(error)\n".utf8))
            return nil
        }
    }
}

struct ListLaunchers: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List launcher apps.")

    func run() throws {
        for name in try Launcher.installer().list() { print(name) }
    }
}

struct GameLauncher: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "game",
        abstract: "Create a launcher app that plays a Steam game.",
        discussion: "The app runs 'barrel play' for the game, so its profile applies, and takes the game's icon.")

    @Option(help: "Bottle with Steam (default: 'steam').") var bottle = "steam"
    @Option(help: "App name (default: the game's name).") var name: String?
    @Option(help: "Extra game profile directory.") var profilesDir: String?
    @Argument(help: "Steam app id or game name (see 'barrel games').") var game: String

    func run() throws {
        let found = try Environment.game(game, bottle: bottle)
        guard let barrel = Bundle.main.executableURL else { throw ValidationError("cannot locate the barrel binary") }
        let spec = LauncherSpec(name: name ?? found.name, bottle: bottle, steamAppID: found.appID,
                                environment: try Environment.launcherEnvironment(),
                                barrelExecutable: barrel.resolvingSymlinksInPath())
        let icon = SteamLibrary.mainExecutable(of: found).flatMap { try? IconConverter.icns(fromExecutable: $0) }
        let app = try Launcher.installer().install(spec, icon: icon)
        print("Created \(app.path)")
    }
}

struct RemoveLauncher: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a launcher app.")

    @Argument var name: String

    func run() throws {
        try Launcher.installer().remove(name)
        print("Removed launcher '\(name)'")
    }
}

Barrel.main()
