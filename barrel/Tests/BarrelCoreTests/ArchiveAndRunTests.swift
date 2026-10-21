import Foundation
import Testing
@testable import BarrelCore

@Suite struct ArchiveTests {
    @Test func exportThenRestoreUnderNewNameRoundTripsContents() throws {
        let f = try Fixture()
        let original = try f.service.create(name: "Office", version: .win7, description: "docs")
        let marker = f.store.prefixURL(for: "Office").appendingPathComponent("drive_c/marker.txt")
        try "hello".write(to: marker, atomically: true, encoding: .utf8)

        let archive = f.root.appendingPathComponent("office.tar.gz")
        try f.service.export("Office", to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))

        let restored = try f.service.restore(from: archive, as: "Office2")
        #expect(restored.name == "Office2")
        #expect(restored.uuid != original.uuid)
        #expect(restored.windowsVersion == .win7)
        #expect(restored.description == "docs")
        let copiedMarker = f.store.prefixURL(for: "Office2").appendingPathComponent("drive_c/marker.txt")
        #expect(try String(contentsOf: copiedMarker, encoding: .utf8) == "hello")
    }

    @Test func restoreKeepsIdentityWhenNameIsFree() throws {
        let source = try Fixture()
        let original = try source.service.create(name: "Games", version: .win10)
        let archive = source.root.appendingPathComponent("games.tar.gz")
        try source.service.export("Games", to: archive)

        let target = try Fixture()
        let restored = try target.service.restore(from: archive)
        #expect(restored == original)
        #expect(try target.service.list().map(\.name) == ["Games"])
    }

    @Test func restoreRejectsExistingName() throws {
        let f = try Fixture()
        _ = try f.service.create(name: "Dup", version: .win10)
        let archive = f.root.appendingPathComponent("dup.tar.gz")
        try f.service.export("Dup", to: archive)
        #expect(throws: BottleError.alreadyExists("Dup")) { try f.service.restore(from: archive) }
    }

    @Test func restoreRejectsArchiveWithoutBottle() throws {
        let f = try Fixture()
        let junk = f.root.appendingPathComponent("junk")
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        try "x".write(to: junk.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let archive = f.root.appendingPathComponent("junk.tar.gz")
        try TarArchiver().archive(directory: junk, to: archive)

        #expect(throws: BottleError.invalidArchive(archive.path)) { try f.service.restore(from: archive) }
    }

    @Test func exportRequiresExistingBottle() throws {
        let f = try Fixture()
        #expect(throws: BottleError.notFound("Nope")) {
            try f.service.export("Nope", to: f.root.appendingPathComponent("x.tar.gz"))
        }
    }
}

@Suite struct RunTests {
    @Test func runUsesNamedBottle() throws {
        let f = try Fixture()
        _ = try f.service.create(name: "Apps", version: .win10)
        let status = try f.service.run("/tmp/setup.exe", arguments: ["/S"], bottle: "Apps")
        #expect(status == 0)
        #expect(f.runtime.calls.last == .start("Apps", "/tmp/setup.exe", ["/S"]))
    }

    @Test func runFallsBackToDefaultBottle() throws {
        let f = try Fixture()
        _ = try f.service.create(name: "Main", version: .win10)
        try f.service.setDefault("Main")
        _ = try f.service.run("/tmp/report.docx", arguments: [], bottle: nil)
        #expect(f.runtime.calls.last == .start("Main", "/tmp/report.docx", []))
    }

    @Test func runWithoutBottleOrDefaultFails() throws {
        let f = try Fixture()
        #expect(throws: BottleError.noDefaultBottle) {
            try f.service.run("/tmp/a.exe", arguments: [], bottle: nil)
        }
    }

    @Test func runRequiresExistingBottle() throws {
        let f = try Fixture()
        #expect(throws: BottleError.notFound("Ghost")) {
            try f.service.run("/tmp/a.exe", arguments: [], bottle: "Ghost")
        }
    }
}
