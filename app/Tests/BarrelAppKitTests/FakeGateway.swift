import BarrelCore
import Foundation
@testable import BarrelAppKit

/// In-memory gateway used to test view models without Wine.
final class FakeGateway: BottleGateway, @unchecked Sendable {
    var bottles: [Bottle]
    var defaultName: String?
    var unavailable: Set<GraphicsBackend> = [.dxvk, .dxmt, .d3dmetal]
    var failure: Error?
    private(set) var runs: [(path: String, bottle: String)] = []
    var recipeList: [RecipeSummary] = []
    private(set) var installs: [(recipe: String, bottle: String?)] = []

    init(bottles: [Bottle] = [], defaultName: String? = nil) {
        self.bottles = bottles
        self.defaultName = defaultName
    }

    private func check() throws { if let failure { throw failure } }

    func list() throws -> [Bottle] { try check(); return bottles }
    func defaultBottle() throws -> String? { try check(); return defaultName }
    func isAvailable(_ backend: GraphicsBackend) -> Bool { !unavailable.contains(backend) }
    func prefixURL(for name: String) -> URL { URL(fileURLWithPath: "/tmp/fake/\(name)") }

    func create(name: String, version: WindowsVersion, description: String?) throws -> Bottle {
        try check()
        let bottle = Bottle(name: name, windowsVersion: version, description: description)
        bottles.append(bottle)
        return bottle
    }
    func copy(_ source: String, to destination: String) throws -> Bottle {
        try check()
        var bottle = bottles.first { $0.name == source }!
        bottle.name = destination
        bottles.append(bottle)
        return bottle
    }
    func delete(_ name: String) throws {
        try check()
        bottles.removeAll { $0.name == name }
        if defaultName == name { defaultName = nil }
    }
    func export(_ name: String, to archive: URL) throws { try check() }
    func restore(from archive: URL, as newName: String?) throws -> Bottle {
        try check()
        let bottle = Bottle(name: newName ?? "restored", windowsVersion: .win10)
        bottles.append(bottle)
        return bottle
    }
    func run(_ path: String, in bottle: String) throws -> Int32 {
        try check()
        runs.append((path, bottle))
        return 0
    }
    func setGraphics(_ name: String, backend: GraphicsBackend) throws {
        try check()
        guard isAvailable(backend) else { throw BottleError.backendUnavailable(backend) }
        if let i = bottles.firstIndex(where: { $0.name == name }) { bottles[i].graphicsBackend = backend }
    }
    func setMSync(_ name: String, enabled: Bool) throws {
        try check()
        if let i = bottles.firstIndex(where: { $0.name == name }) { bottles[i].msync = enabled }
    }
    func setDefault(_ name: String?) throws { try check(); defaultName = name }
    func recipes() throws -> [RecipeSummary] { try check(); return recipeList }
    func install(recipe: String, bottle: String?) throws -> String {
        try check()
        installs.append((recipe, bottle))
        let name = bottle ?? recipe
        if !bottles.contains(where: { $0.name == name }) { bottles.append(Bottle(name: name, windowsVersion: .win10)) }
        return name
    }
}
