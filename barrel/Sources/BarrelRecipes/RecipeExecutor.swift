import BarrelCore
import Foundation

/// Port: the bottle operations recipes need. `BottleService` is adapted by `BottleServiceHost`.
public protocol RecipeHost {
    func bottleExists(_ name: String) -> Bool
    func createBottle(name: String, version: WindowsVersion, description: String?) throws
    func setGraphics(_ name: String, backend: GraphicsBackend) throws
    func setMSync(_ name: String, enabled: Bool) throws
    func setAppGraphics(_ name: String, executable: String, backend: GraphicsBackend) throws
    func prefixURL(for name: String) -> URL
    /// Runs a program (Unix path) inside the bottle and waits; returns its exit status.
    func run(_ path: String, arguments: [String], bottle: String) throws -> Int32
}

public struct BottleServiceHost: RecipeHost {
    let service: BottleService
    let store: BottleStore

    public init(service: BottleService, store: BottleStore) {
        self.service = service
        self.store = store
    }

    public func bottleExists(_ name: String) -> Bool { store.exists(name) }

    public func createBottle(name: String, version: WindowsVersion, description: String?) throws {
        try service.create(name: name, version: version, description: description)
    }

    public func setGraphics(_ name: String, backend: GraphicsBackend) throws {
        try service.setGraphics(name, backend: backend)
    }

    public func setMSync(_ name: String, enabled: Bool) throws { try service.setMSync(name, enabled: enabled) }
    public func setAppGraphics(_ name: String, executable: String, backend: GraphicsBackend) throws {
        try service.setAppGraphics(name, executable: executable, backend: backend)
    }
    public func prefixURL(for name: String) -> URL { store.prefixURL(for: name) }

    public func run(_ path: String, arguments: [String], bottle: String) throws -> Int32 {
        try service.run(path, arguments: arguments, bottle: bottle)
    }
}

public struct RecipeExecutor {
    let host: RecipeHost
    let downloads: DownloadCache
    let log: (String) -> Void

    public init(host: RecipeHost, downloads: DownloadCache, log: @escaping (String) -> Void = { _ in }) {
        self.host = host
        self.downloads = downloads
        self.log = log
    }

    /// Wine registry key holding per-application DLL overrides.
    static let dllOverridesKey = "HKCU\\Software\\Wine\\DllOverrides"

    /// Installs `id` and its dependencies into `bottle` (default: the recipe id), creating the bottle if needed.
    /// Returns the bottle name.
    @discardableResult
    public func install(_ id: String, catalog: RecipeCatalog, bottle: String? = nil) throws -> String {
        let order = try catalog.installOrder(for: id)
        let root = order[order.count - 1]
        let name = bottle ?? root.id

        try prepareBottle(name, for: root)
        for recipe in order {
            log("Recipe \(recipe.id): \(recipe.name)")
            for (offset, step) in recipe.steps.enumerated() {
                do {
                    try apply(step, bottle: name)
                } catch let error as RecipeError {
                    throw RecipeError.stepFailed(recipe: recipe.id, step: offset + 1, reason: "\(error)")
                } catch {
                    throw RecipeError.stepFailed(recipe: recipe.id, step: offset + 1, reason: "\(error)")
                }
            }
        }
        return name
    }

    private func prepareBottle(_ name: String, for recipe: Recipe) throws {
        let settings = recipe.bottle
        if !host.bottleExists(name) {
            log("Creating bottle '\(name)'")
            try host.createBottle(name: name, version: settings.windowsVersion ?? .win10, description: recipe.name)
        }
        if let backend = settings.graphicsBackend { try host.setGraphics(name, backend: backend) }
        if let msync = settings.msync { try host.setMSync(name, enabled: msync) }
        for executable in settings.appGraphics.keys.sorted() {
            try host.setAppGraphics(name, executable: executable, backend: settings.appGraphics[executable]!)
        }
    }

    private func apply(_ step: Step, bottle: String) throws {
        switch step {
        case .download(let download):
            log("Downloading \(download.fileName)")
            try downloads.fetch(download)
        case .run(let run):
            try apply(run, bottle: bottle)
        case .registry(let value):
            try addRegistry(key: value.key, name: value.name, type: value.type, data: value.data, bottle: bottle)
        case .dllOverride(let override):
            try addRegistry(key: Self.dllOverridesKey, name: override.dll, type: .string,
                            data: override.mode.registryData, bottle: bottle)
        }
    }

    private func apply(_ run: RunStep, bottle: String) throws {
        let path: String
        if let file = run.file {
            path = downloads.localURL(for: file).path
        } else if let windowsPath = run.path, let unix = unixPath(forWindows: windowsPath, bottle: bottle) {
            path = unix
        } else {
            path = run.path ?? ""
        }
        log("Running \(path)")
        let status = try host.run(path, arguments: run.arguments, bottle: bottle)
        guard run.expectedExitCodes.contains(status) else {
            throw RecipeError.invalidValue(field: "run", reason: "'\(path)' exited with status \(status)")
        }
    }

    /// `C:\dir\file` becomes `<prefix>/drive_c/dir/file`; Unix paths are left alone.
    func unixPath(forWindows path: String, bottle: String) -> String? {
        let scalars = Array(path)
        guard scalars.count >= 3, scalars[1] == ":", scalars[2] == "\\" || scalars[2] == "/",
              scalars[0].lowercased() == "c" else { return nil }
        let relative = String(scalars.dropFirst(3)).replacingOccurrences(of: "\\", with: "/")
        return host.prefixURL(for: bottle).appendingPathComponent("drive_c/\(relative)").path
    }

    private func addRegistry(key: String, name: String, type: RegistryType, data: String, bottle: String) throws {
        let regExe = host.prefixURL(for: bottle).appendingPathComponent("drive_c/windows/system32/reg.exe").path
        let arguments = Self.registryArguments(key: key, name: name, type: type, data: data)
        log("Registry \(key)\\\(name)")
        let status = try host.run(regExe, arguments: arguments, bottle: bottle)
        guard status == 0 else {
            throw RecipeError.invalidValue(field: "registry", reason: "reg.exe exited with status \(status)")
        }
    }

    static func registryArguments(key: String, name: String, type: RegistryType, data: String) -> [String] {
        ["add", key, "/v", name, "/t", type.rawValue, "/d", data, "/f"]
    }
}
