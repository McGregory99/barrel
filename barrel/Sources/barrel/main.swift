import ArgumentParser
import BarrelCore
import BarrelRecipes
import Foundation

struct Barrel: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage Wine bottles on macOS.",
        discussion: """
            Environment:
              BARREL_HOME  Data directory (default: ~/Library/Application Support/Barrel)
              BARREL_WINE  Path to the wine binary (default: 'wine' found in PATH)
              BARREL_LIBS  Directory with native libraries such as libMoltenVK.dylib
              BARREL_DXVK  DXVK build directory (x64/, x32/)
              BARREL_DXMT  DXMT build directory (x64/, x32/)
              BARREL_GPTK  Your Apple Game Porting Toolkit directory (wine/, external/)
            """,
        subcommands: [Create.self, List.self, Info.self, Copy.self, Delete.self, Default.self, Templates.self,
                      Export.self, Restore.self, Run.self, Graphics.self, MSync.self,
                      Recipes.self, Install.self]
    )
}

struct Environment {
    static func service() throws -> BottleService {
        BottleService(store: try FileBottleStore(root: home()), runtime: ProcessWineRuntime(wineBinary: try wine()),
                      components: components())
    }

    static func components() -> RuntimeComponents {
        let env = ProcessInfo.processInfo.environment
        func directory(_ key: String) -> URL? { env[key].map { URL(fileURLWithPath: $0, isDirectory: true) } }
        return RuntimeComponents(libraryDirectory: directory("BARREL_LIBS"), dxvkDirectory: directory("BARREL_DXVK"),
                                 dxmtDirectory: directory("BARREL_DXMT"), gptkDirectory: directory("BARREL_GPTK"))
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
        abstract: "Show or set a bottle's Direct3D backend.",
        discussion: """
            Backends: wined3d (built in), dxvk (needs BARREL_DXVK and libMoltenVK in BARREL_LIBS),
            dxmt (needs BARREL_DXMT), d3dmetal (needs BARREL_GPTK pointing to your own copy of
            Apple's Game Porting Toolkit; it is not redistributable).
            """)

    @Argument var name: String
    @Argument(help: "wined3d, dxvk, dxmt or d3dmetal.") var backend: String?

    func run() throws {
        let service = try Environment.service()
        guard let backend else {
            print(try service.info(name).graphicsBackend.rawValue)
            return
        }
        try service.setGraphics(name, backend: try GraphicsBackend(name: backend))
        print("Bottle '\(name)' now uses \(backend.lowercased())")
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
        return RecipeCatalog.load(directories: directories)
    }
}

struct Recipes: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List available install recipes.")

    @Option(help: "Extra recipe directory (also reads $BARREL_HOME/Recipes).") var recipesDir: String?

    func run() throws {
        let catalog = Environment.catalog(extra: recipesDir)
        for recipe in catalog.sorted { print("\(recipe.id)\t\(recipe.name)") }
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
    @Option(help: "Extra recipe directory (also reads $BARREL_HOME/Recipes).") var recipesDir: String?

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

Barrel.main()
