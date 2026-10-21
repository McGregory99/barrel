import BarrelCore
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

    // MARK: Plumbing

    /// Runs a mutating call, then reloads the list. A returned name (or `select`) becomes the selection.
    private func mutate<T>(_ message: String?, select: String? = nil,
                           _ work: @escaping @Sendable (BottleGateway) throws -> T) async {
        var succeeded = false
        await perform(message) { gateway in
            _ = try work(gateway)
            let list = try gateway.list()
            return (list, try gateway.defaultBottle())
        } apply: { [self] result in
            apply(bottles: result.0, defaultName: result.1)
            succeeded = true
        }
        if succeeded, let select { selection = select }
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
        default: error.localizedDescription
        }
    }
}
