import Foundation
import Testing
@testable import BarrelCore

/// Builds a small synthetic `appinfo.vdf` (version 28 with inline keys, or 29 with a string table).
struct AppInfoBuilder {
    enum Node { case string(String), int(Int32), block([(String, Node)]) }
    var version: UInt8 = 0x29
    var apps: [(Int, [(String, Node)])] = []

    func data() -> Data {
        var keys: [String] = []
        func key(_ name: String, into out: inout Data) {
            if version >= 0x29 {
                let index = keys.firstIndex(of: name) ?? { keys.append(name); return keys.count - 1 }()
                out.append(u32(UInt32(index)))
            } else {
                out.append(contentsOf: Array(name.utf8) + [0])
            }
        }
        func encode(_ entries: [(String, Node)], into out: inout Data) {
            for (name, node) in entries {
                switch node {
                case .string(let s): out.append(1); key(name, into: &out); out.append(contentsOf: Array(s.utf8) + [0])
                case .int(let i): out.append(2); key(name, into: &out); out.append(u32(UInt32(bitPattern: i)))
                case .block(let children): out.append(0); key(name, into: &out); encode(children, into: &out); out.append(8)
                }
            }
        }
        var body = Data()
        for (appID, entries) in apps {
            var kv = Data()
            encode(entries, into: &kv)
            kv.append(8)
            // info state, last updated, PICS token, SHA-1, change number, binary SHA-1.
            let fixed = Data(count: 4 + 4 + 8 + 20 + 4 + 20)
            body.append(u32(UInt32(appID)))
            body.append(u32(UInt32(fixed.count + kv.count)))
            body.append(fixed + kv)
        }
        body.append(u32(0))
        var out = Data([version, 0x44, 0x56, 0x07]) + u32(1)
        if version >= 0x29 {
            out.append(u64(UInt64(out.count + 8 + body.count)))
            out.append(body)
            out.append(u32(UInt32(keys.count)))
            for name in keys { out.append(contentsOf: Array(name.utf8) + [0]) }
        } else {
            out.append(body)
        }
        return out
    }

    private func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private func u64(_ v: UInt64) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    static func app(_ id: Int, name: String, type: String, icon: String? = nil) -> (Int, [(String, Node)]) {
        var common: [(String, Node)] = [("name", .string(name)), ("type", .string(type))]
        if let icon { common.append(("clienticon", .string(icon))) }
        return (id, [("appinfo", .block([("appid", .int(Int32(id))), ("common", .block(common))]))])
    }
}

@Suite struct SteamAppInfoTests {
    @Test(arguments: [UInt8(0x28), UInt8(0x29)])
    func readsNameAndTypeOfTheRequestedApps(version: UInt8) throws {
        var builder = AppInfoBuilder(version: version)
        builder.apps = [AppInfoBuilder.app(10, name: "Counter-Strike", type: "Game"),
                        AppInfoBuilder.app(228980, name: "Steamworks Common Redistributables", type: "Tool"),
                        AppInfoBuilder.app(20, name: "Team Fortress Classic", type: "game")]
        let apps = try SteamAppInfo.parse(builder.data(), appIDs: [10, 228980])
        #expect(apps.keys.sorted() == [10, 228980])
        #expect(apps[10]?["appinfo"]?["common"]?["name"]?.string == "Counter-Strike")
        #expect(apps[10]?["appinfo"]?["appid"]?.string == "10")
        #expect(apps[228980]?["appinfo"]?["common"]?["type"]?.string == "Tool")
    }

    @Test func rejectsFilesThatAreNotAppInfo() {
        #expect(throws: SteamAppInfoError.self) { try SteamAppInfo.parse(Data("hello world!".utf8), appIDs: [1]) }
        var truncated = AppInfoBuilder()
        truncated.apps = [AppInfoBuilder.app(10, name: "Counter-Strike", type: "Game")]
        let data = truncated.data()
        #expect(throws: SteamAppInfoError.self) { try SteamAppInfo.parse(data.prefix(40), appIDs: [10]) }
    }
}

@Suite struct SteamLibraryOwnedGamesTests {
    /// A Steam folder whose library cache holds artwork for `cached` and whose appinfo knows `apps`.
    func makeSteam(cached: [Int], apps: [(Int, [(String, AppInfoBuilder.Node)])], installed: [Int] = []) throws -> URL {
        let prefix = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let steam = SteamLibrary.steamDirectory(prefix: prefix)
        let cache = steam.appendingPathComponent("appcache/librarycache", isDirectory: true)
        for id in cached {
            let folder = cache.appendingPathComponent("\(id)/abc123", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("jpg".utf8).write(to: folder.appendingPathComponent("library_capsule.jpg"))
            try Data("icon".utf8).write(to: cache.appendingPathComponent("\(id)/icon\(id).jpg"))
        }
        var builder = AppInfoBuilder()
        builder.apps = apps
        try builder.data().write(to: steam.appendingPathComponent("appcache/appinfo.vdf"))
        let steamapps = steam.appendingPathComponent("steamapps", isDirectory: true)
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        for id in installed {
            try """
            "AppState" { "appid" "\(id)" "name" "Installed \(id)" "installdir" "G\(id)" "StateFlags" "4" }
            """.write(to: steamapps.appendingPathComponent("appmanifest_\(id).acf"), atomically: true, encoding: .utf8)
        }
        return prefix
    }

    @Test func listsCachedGamesThatAreNotInstalledWithTheirArtwork() throws {
        let prefix = try makeSteam(
            cached: [10, 20, 30, 228980, 40],
            apps: [AppInfoBuilder.app(10, name: "Zeta", type: "Game", icon: "icon10"),
                   AppInfoBuilder.app(20, name: "alpha", type: "game"),
                   AppInfoBuilder.app(30, name: "Installed One", type: "Game"),
                   AppInfoBuilder.app(228980, name: "Redistributables", type: "Game"),
                   AppInfoBuilder.app(40, name: "Soundtrack", type: "Music"),
                   AppInfoBuilder.app(50, name: "Not In Library", type: "Game")],
            installed: [30])
        defer { try? FileManager.default.removeItem(at: prefix) }

        let games = SteamLibrary.uninstalledGames(prefix: prefix)

        #expect(games.map(\.appID) == [20, 10])
        #expect(games.map(\.name) == ["alpha", "Zeta"])
        #expect(games[1].icon?.lastPathComponent == "icon10.jpg")
        #expect(games[0].icon == nil)
        #expect(games[0].artwork?.lastPathComponent == "library_capsule.jpg")
    }

    @Test func withoutAppInfoThereAreNoOtherGames() throws {
        let prefix = try makeSteam(cached: [10], apps: [])
        defer { try? FileManager.default.removeItem(at: prefix) }
        try FileManager.default.removeItem(at: SteamLibrary.steamDirectory(prefix: prefix)
            .appendingPathComponent("appcache/appinfo.vdf"))
        #expect(SteamLibrary.uninstalledGames(prefix: prefix).isEmpty)
    }
}
