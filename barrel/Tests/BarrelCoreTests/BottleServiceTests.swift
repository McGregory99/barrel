import Foundation
import Testing
@testable import BarrelCore

final class FakeWineRuntime: WineRuntime {
    enum Call: Equatable {
        case initialize(String)
        case setVersion(String, String)
        case shutdown(String)
        case start(String, String, [String])
    }

    var calls: [Call] = []
    var failOnInitialize = false

    func initializePrefix(at prefix: URL) throws {
        calls.append(.initialize(prefix.lastPathComponent))
        if failOnInitialize { throw WineRuntimeError.commandFailed(command: "wineboot", status: 1) }
        try FileManager.default.createDirectory(
            at: prefix.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
    }

    func setWindowsVersion(_ version: WindowsVersion, prefix: URL) throws {
        calls.append(.setVersion(prefix.lastPathComponent, version.winecfgName))
    }

    func shutdown(prefix: URL) throws {
        calls.append(.shutdown(prefix.lastPathComponent))
    }

    var lastEnvironment: [String: String] = [:]

    func start(_ path: String, arguments: [String], prefix: URL, environment: [String: String]) throws -> Int32 {
        calls.append(.start(prefix.lastPathComponent, path, arguments))
        lastEnvironment = environment
        return 0
    }
}

struct Fixture {
    let root: URL
    let runtime = FakeWineRuntime()
    let store: FileBottleStore
    let service: BottleService

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("barrel-tests-\(UUID().uuidString)")
        store = try FileBottleStore(root: root)
        service = BottleService(store: store, runtime: runtime)
    }

    func bottleExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: store.prefixURL(for: name).path)
    }
}

@Suite struct WindowsVersionTests {
    @Test func parsesTemplateIdentifiers() throws {
        #expect(try WindowsVersion(template: "win10") == .win10)
        #expect(try WindowsVersion(template: "win10_64") == .win10)
        #expect(try WindowsVersion(template: "winxp") == .winxp)
        #expect(try WindowsVersion(template: "win11_64") == .win11)
    }

    @Test func rejectsUnknownTemplate() {
        #expect(throws: BottleError.unknownTemplate("win95")) {
            try WindowsVersion(template: "win95")
        }
    }

    @Test func mapsToWinecfgNames() {
        #expect(WindowsVersion.win2000.winecfgName == "win2k")
        #expect(WindowsVersion.winvista.winecfgName == "vista")
        #expect(WindowsVersion.win11.winecfgName == "win11")
    }
}

@Suite struct BottleServiceTests {
    @Test func createWritesMetadataAndInitializesPrefix() throws {
        let f = try Fixture()
        let bottle = try f.service.create(name: "Steam", version: .win10, description: "games")

        #expect(bottle.name == "Steam")
        #expect(bottle.windowsVersion == .win10)
        #expect(bottle.description == "games")
        #expect(f.bottleExists("Steam"))
        #expect(try f.store.load("Steam") == bottle)
        #expect(f.runtime.calls == [.initialize("Steam"), .setVersion("Steam", "win10")])
    }

    @Test func createRejectsDuplicateName() throws {
        let f = try Fixture()
        _ = try f.service.create(name: "Office", version: .win7)
        #expect(throws: BottleError.alreadyExists("Office")) {
            try f.service.create(name: "Office", version: .win10)
        }
    }

    @Test(arguments: ["", ".", "..", "a/b", ".hidden"])
    func createRejectsInvalidNames(name: String) throws {
        let f = try Fixture()
        #expect(throws: BottleError.invalidName(name)) {
            try f.service.create(name: name, version: .win10)
        }
        #expect(f.runtime.calls.isEmpty)
    }

    @Test func createRollsBackWhenPrefixInitializationFails() throws {
        let f = try Fixture()
        f.runtime.failOnInitialize = true
        #expect(throws: WineRuntimeError.commandFailed(command: "wineboot", status: 1)) {
            try f.service.create(name: "Broken", version: .win10)
        }
        #expect(!f.bottleExists("Broken"))
        #expect(try f.service.list().isEmpty)
    }

    @Test func listReturnsBottlesSortedByName() throws {
        let f = try Fixture()
        _ = try f.service.create(name: "zeta", version: .win10)
        _ = try f.service.create(name: "Alpha", version: .win7)
        #expect(try f.service.list().map(\.name) == ["Alpha", "zeta"])
    }

    @Test func copyCreatesIndependentBottleWithNewIdentity() throws {
        let f = try Fixture()
        let source = try f.service.create(name: "Base", version: .win8)
        let copy = try f.service.copy("Base", to: "Clone")

        #expect(copy.name == "Clone")
        #expect(copy.uuid != source.uuid)
        #expect(copy.windowsVersion == .win8)
        #expect(f.bottleExists("Clone"))
        #expect(try f.store.load("Base") == source)
        #expect(FileManager.default.fileExists(
            atPath: f.store.prefixURL(for: "Clone").appendingPathComponent("drive_c").path))
    }

    @Test func copyRejectsExistingDestinationAndMissingSource() throws {
        let f = try Fixture()
        _ = try f.service.create(name: "A", version: .win10)
        _ = try f.service.create(name: "B", version: .win10)
        #expect(throws: BottleError.alreadyExists("B")) { try f.service.copy("A", to: "B") }
        #expect(throws: BottleError.notFound("Nope")) { try f.service.copy("Nope", to: "C") }
    }

    @Test func deleteStopsWineAndRemovesBottle() throws {
        let f = try Fixture()
        _ = try f.service.create(name: "Temp", version: .win10)
        try f.service.delete("Temp")

        #expect(!f.bottleExists("Temp"))
        #expect(f.runtime.calls.last == .shutdown("Temp"))
        #expect(throws: BottleError.notFound("Temp")) { try f.service.delete("Temp") }
    }

    @Test func defaultBottlePersistsAndIsClearedOnDelete() throws {
        let f = try Fixture()
        _ = try f.service.create(name: "Main", version: .win10)
        try f.service.setDefault("Main")

        let reopened = try FileBottleStore(root: f.root)
        #expect(try reopened.defaultBottleName() == "Main")

        try f.service.delete("Main")
        #expect(try f.store.defaultBottleName() == nil)
    }

    @Test func setDefaultRequiresExistingBottle() throws {
        let f = try Fixture()
        #expect(throws: BottleError.notFound("Ghost")) { try f.service.setDefault("Ghost") }
    }
}
