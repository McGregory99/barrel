import BarrelCore
import Foundation
import Testing

/// Every test uses `MemoryDockStore`; none reads or changes the real Dock.
struct DockTests {
    let app = URL(fileURLWithPath: "/Users/me/Applications/Barrel/Stonewards.app", isDirectory: true)

    static func tile(_ url: String, label: String) -> [String: Any] {
        ["tile-type": "file-tile", "GUID": 7,
         "tile-data": ["file-data": ["_CFURLString": url, "_CFURLStringType": 15], "file-label": label]]
    }

    static func urls(_ store: MemoryDockStore) -> [String?] {
        store.apps.map { (($0 as? [String: Any])?["tile-data"] as? [String: Any])
            .flatMap { ($0["file-data"] as? [String: Any])?["_CFURLString"] as? String } }
    }

    @Test func addingAnAppAddsOneTileAndAddingAgainDoesNotDuplicateIt() throws {
        let store = MemoryDockStore()
        let dock = Dock(store: store)
        #expect(!dock.contains(app))

        try dock.add(app, label: "Stonewards")
        try dock.add(app, label: "Stonewards")

        #expect(dock.contains(app))
        #expect(Self.urls(store) == ["file:///Users/me/Applications/Barrel/Stonewards.app/"])
        let tile = try #require(store.apps.first as? [String: Any])
        #expect(tile["tile-type"] as? String == "file-tile")
        let data = try #require(tile["tile-data"] as? [String: Any])
        #expect(data["file-label"] as? String == "Stonewards")
        #expect((data["file-data"] as? [String: Any])?["_CFURLStringType"] as? Int == 15)
        #expect(store.writes == 1)
    }

    @Test func unrelatedTilesKeepTheirOrderAndTheNewTileGoesLast() throws {
        let store = MemoryDockStore(apps: [Self.tile("file:///System/Applications/Mail.app/", label: "Mail"),
                                           ["tile-type": "spacer-tile", "tile-data": [String: Any]()],
                                           Self.tile("file:///Applications/Safari.app/", label: "Safari")])
        let dock = Dock(store: store)

        try dock.add(app, label: "Stonewards")
        #expect(Self.urls(store) == ["file:///System/Applications/Mail.app/", nil, "file:///Applications/Safari.app/",
                                     "file:///Users/me/Applications/Barrel/Stonewards.app/"])
        #expect((store.apps[0] as? [String: Any])?["GUID"] as? Int == 7)

        try dock.remove(app)
        #expect(Self.urls(store) == ["file:///System/Applications/Mail.app/", nil, "file:///Applications/Safari.app/"])
        #expect((store.apps[1] as? [String: Any])?["tile-type"] as? String == "spacer-tile")
    }

    @Test func tilesMatchWithoutTrailingSlashAndWithPercentEncoding() throws {
        let aoe = URL(fileURLWithPath: "/Users/me/Applications/Barrel/Age of Empires II - Definitive Edition.app")
        let store = MemoryDockStore(apps: [
            Self.tile("file:///Users/me/Applications/Barrel/Age%20of%20Empires%20II%20-%20Definitive%20Edition.app", label: "AoE"),
            Self.tile("file:///Users/me/Applications/Barrel/Stonewards.app", label: "Stonewards")])
        let dock = Dock(store: store)

        #expect(dock.contains(aoe))
        #expect(dock.contains(app))
        try dock.add(aoe, label: "AoE")
        #expect(store.apps.count == 2)
        #expect(store.writes == 0)

        try dock.remove(aoe)
        #expect(Self.urls(store) == ["file:///Users/me/Applications/Barrel/Stonewards.app"])
    }

    @Test func tilesMatchThroughSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real"), link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real.appendingPathComponent("Game.app"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = MemoryDockStore(apps: [Self.tile(real.appendingPathComponent("Game.app").absoluteString, label: "Game")])

        #expect(Dock(store: store).contains(link.appendingPathComponent("Game.app")))
    }

    @Test func removingAnAppWithoutATileChangesNothing() throws {
        let store = MemoryDockStore(apps: [Self.tile("file:///Applications/Safari.app/", label: "Safari")])
        try Dock(store: store).remove(app)
        #expect(store.writes == 0)
        #expect(store.apps.count == 1)
    }

    @Test func anUnreadableDockIsNeverOverwritten() {
        let store = MemoryDockStore(apps: nil)
        let dock = Dock(store: store)
        #expect(!dock.contains(app))
        #expect(throws: DockError.unreadable) { try dock.add(app, label: "Stonewards") }
        #expect(store.writes == 0)
    }
}
