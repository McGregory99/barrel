import Foundation

/// Bottle use cases: create, copy, delete, archive, run and default selection.
public struct BottleService {
    let store: BottleStore
    let runtime: WineRuntime
    let archiver: Archiver
    let graphics: GraphicsInstaller
    let components: RuntimeComponents

    public init(store: BottleStore, runtime: WineRuntime, archiver: Archiver = TarArchiver(),
                graphics: GraphicsInstaller = FileGraphicsInstaller(),
                components: RuntimeComponents = RuntimeComponents()) {
        self.store = store
        self.runtime = runtime
        self.archiver = archiver
        self.graphics = graphics
        self.components = components
    }

    @discardableResult
    public func create(name: String, version: WindowsVersion, description: String? = nil) throws -> Bottle {
        try validate(name)
        guard !store.exists(name) else { throw BottleError.alreadyExists(name) }

        let bottle = Bottle(name: name, windowsVersion: version, description: description)
        try store.save(bottle)
        do {
            let prefix = store.prefixURL(for: name)
            let environment = LaunchEnvironment.make(for: bottle, components: components)
            try runtime.initializePrefix(at: prefix, environment: environment)
            try runtime.setWindowsVersion(version, prefix: prefix, environment: environment)
        } catch {
            try? store.remove(name)
            throw error
        }
        return bottle
    }

    public func list() throws -> [Bottle] {
        try store.list()
    }

    public func info(_ name: String) throws -> Bottle {
        try store.load(name)
    }

    @discardableResult
    public func copy(_ source: String, to destination: String) throws -> Bottle {
        try validate(destination)
        var bottle = try store.load(source)
        guard !store.exists(destination) else { throw BottleError.alreadyExists(destination) }

        try runtime.shutdown(prefix: store.prefixURL(for: source))
        try store.duplicate(source, to: destination)
        bottle.name = destination
        bottle.uuid = UUID()
        bottle.createdAt = Bottle.wholeSeconds(Date())
        try store.save(bottle)
        return bottle
    }

    public func delete(_ name: String) throws {
        guard store.exists(name) else { throw BottleError.notFound(name) }
        try runtime.shutdown(prefix: store.prefixURL(for: name))
        try store.remove(name)
        if try store.defaultBottleName() == name {
            try store.setDefaultBottleName(nil)
        }
    }

    public func export(_ name: String, to archive: URL) throws {
        guard store.exists(name) else { throw BottleError.notFound(name) }
        try runtime.shutdown(prefix: store.prefixURL(for: name))
        try archiver.archive(directory: store.prefixURL(for: name), to: archive)
    }

    /// Restores an exported bottle. Restoring under a new name gives it a new identity.
    @discardableResult
    public func restore(from archive: URL, as newName: String? = nil) throws -> Bottle {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent("barrel-restore-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try archiver.extract(archive, into: staging)
        let entries = try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        guard entries.count == 1, var bottle = try? store.readBottle(at: entries[0]) else {
            throw BottleError.invalidArchive(archive.path)
        }

        let name = newName ?? bottle.name
        try validate(name)
        guard !store.exists(name) else { throw BottleError.alreadyExists(name) }
        if name != bottle.name {
            bottle.name = name
            bottle.uuid = UUID()
        }
        try store.adopt(entries[0], as: name)
        try store.save(bottle)
        return bottle
    }

    /// Opens a program or document in `bottle`, or in the default bottle when nil.
    public func run(_ path: String, arguments: [String], bottle: String?) throws -> Int32 {
        guard let name = try bottle ?? store.defaultBottleName() else { throw BottleError.noDefaultBottle }
        let selected = try store.load(name)
        return try runtime.start(path, arguments: arguments, prefix: store.prefixURL(for: name),
                                 environment: LaunchEnvironment.make(for: selected, components: components))
    }

    /// Sets the bottle-wide backend: installs its DLLs and writes the global Direct3D load order.
    public func setGraphics(_ name: String, backend: GraphicsBackend) throws {
        var bottle = try store.load(name)
        guard components.isAvailable(backend) else { throw BottleError.backendUnavailable(backend) }
        let prefix = store.prefixURL(for: name)
        try graphics.install(backend, into: prefix, components: components)
        try writeDirect3DOverrides(key: #"HKCU\Software\Wine\DllOverrides"#, backend: backend, bottle: bottle)
        bottle.graphicsBackend = backend
        try store.save(bottle)
    }

    /// Overrides the backend for one executable (by file name) through Wine's AppDefaults.
    public func setAppGraphics(_ name: String, executable: String, backend: GraphicsBackend) throws {
        var bottle = try store.load(name)
        guard !executable.isEmpty, executable.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\")) == nil
        else { throw BottleError.invalidExecutable(executable) }
        guard backend.supportsPerApp else { throw BottleError.backendNotPerApp(backend) }
        guard components.isAvailable(backend) else { throw BottleError.backendUnavailable(backend) }
        let prefix = store.prefixURL(for: name)
        try graphics.install(backend, into: prefix, components: components)
        try writeDirect3DOverrides(key: #"HKCU\Software\Wine\AppDefaults\"# + executable + #"\DllOverrides"#,
                                   backend: backend, bottle: bottle)
        bottle.appGraphics[executable] = backend
        try store.save(bottle)
    }

    private func writeDirect3DOverrides(key: String, backend: GraphicsBackend, bottle: Bottle) throws {
        let prefix = store.prefixURL(for: bottle.name)
        let environment = LaunchEnvironment.make(for: bottle, components: components)
        for dll in LaunchEnvironment.direct3DLibraries {
            try runtime.setRegistryValue(key: key, name: dll, data: backend.dllOverrideMode, prefix: prefix,
                                         environment: environment)
        }
    }

    public func setMSync(_ name: String, enabled: Bool) throws {
        var bottle = try store.load(name)
        bottle.msync = enabled
        try store.save(bottle)
    }

    public func setDefault(_ name: String?) throws {
        if let name, !store.exists(name) { throw BottleError.notFound(name) }
        try store.setDefaultBottleName(name)
    }

    public func defaultBottle() throws -> String? {
        try store.defaultBottleName()
    }

    private func validate(_ name: String) throws {
        let forbidden = CharacterSet(charactersIn: "/:\0")
        guard !name.isEmpty, !name.hasPrefix("."), name.count <= 128,
              name.rangeOfCharacter(from: forbidden) == nil
        else { throw BottleError.invalidName(name) }
    }
}
