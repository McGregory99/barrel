import ArgumentParser
import BarrelCore
import Foundation

struct Barrel: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage Wine bottles on macOS.",
        discussion: """
            Environment:
              BARREL_HOME  Data directory (default: ~/Library/Application Support/Barrel)
              BARREL_WINE  Path to the wine binary (default: 'wine' found in PATH)
            """,
        subcommands: [Create.self, List.self, Info.self, Copy.self, Delete.self, Default.self, Templates.self,
                      Export.self, Restore.self, Run.self]
    )
}

struct Environment {
    static func service() throws -> BottleService {
        BottleService(store: try FileBottleStore(root: home()), runtime: ProcessWineRuntime(wineBinary: try wine()))
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

Barrel.main()
