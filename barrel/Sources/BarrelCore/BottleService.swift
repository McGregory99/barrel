import Foundation

/// Bottle use cases: create, copy, delete, list and default selection.
public struct BottleService {
    let store: BottleStore
    let runtime: WineRuntime

    public init(store: BottleStore, runtime: WineRuntime) {
        self.store = store
        self.runtime = runtime
    }

    @discardableResult
    public func create(name: String, version: WindowsVersion, description: String? = nil) throws -> Bottle {
        try validate(name)
        guard !store.exists(name) else { throw BottleError.alreadyExists(name) }

        let bottle = Bottle(name: name, windowsVersion: version, description: description)
        try store.save(bottle)
        do {
            let prefix = store.prefixURL(for: name)
            try runtime.initializePrefix(at: prefix)
            try runtime.setWindowsVersion(version, prefix: prefix)
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
