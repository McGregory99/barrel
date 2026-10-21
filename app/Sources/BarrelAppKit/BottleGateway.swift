import BarrelCore
import Foundation

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
}

/// Adapter from the gateway port to `BottleService`.
public final class BarrelCoreGateway: BottleGateway, @unchecked Sendable {
    private let service: BottleService
    private let store: BottleStore
    private let components: RuntimeComponents

    public init(store: BottleStore, wineBinary: URL, components: RuntimeComponents) {
        self.store = store
        self.components = components
        self.service = BottleService(store: store, runtime: ProcessWineRuntime(wineBinary: wineBinary),
                                     components: components)
    }

    /// Builds the production gateway from user settings, creating the data directory if needed.
    public convenience init(settings: AppSettings) throws {
        try self.init(store: FileBottleStore(root: settings.dataDirectory),
                      wineBinary: settings.resolvedWineBinary, components: settings.components)
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
}
