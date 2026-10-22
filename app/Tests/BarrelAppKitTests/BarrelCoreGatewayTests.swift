import BarrelCore
import Foundation
import Testing
@testable import BarrelAppKit

struct BarrelCoreGatewayTests {
    @Test func recipesComeFromTheConfiguredFoldersSortedById() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gateway-\(UUID().uuidString)")
        let recipes = root.appendingPathComponent("recipes")
        try FileManager.default.createDirectory(at: recipes, withIntermediateDirectories: true)
        for (id, name) in [("zeta", "Zeta App"), ("alpha", "Alpha App")] {
            let json = #"{"formatVersion":1,"id":"\#(id)","name":"\#(name)","description":"d","steps":[]}"#
            try Data(json.utf8).write(to: recipes.appendingPathComponent("\(id).json"))
        }
        var settings = AppSettings(dataDirectory: root.appendingPathComponent("data"))
        settings.wineBinary = "/nonexistent/wine"
        settings.recipesDirectory = recipes.path

        let gateway = try BarrelCoreGateway(settings: settings)

        #expect(try gateway.recipes() == [RecipeSummary(id: "alpha", name: "Alpha App", description: "d"),
                                          RecipeSummary(id: "zeta", name: "Zeta App", description: "d")])
    }

    @Test func findsTheSteamBottleAndItsGamesWithProfiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gateway-\(UUID().uuidString)")
        let data = root.appendingPathComponent("data"), profiles = root.appendingPathComponent("profiles")
        let store = try FileBottleStore(root: data)
        for name in ["Office", "steam"] {
            try store.save(Bottle(name: name, windowsVersion: .win10))
            try FileManager.default.createDirectory(at: store.prefixURL(for: name), withIntermediateDirectories: true)
        }
        let steam = SteamLibrary.steamDirectory(prefix: store.prefixURL(for: "steam"))
        let game = steam.appendingPathComponent("steamapps/common/Stonewards")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: steam.appendingPathComponent("steam.exe"))
        try Data("MZ".utf8).write(to: game.appendingPathComponent("Stonewards.exe"))
        try Data(#""AppState" { "appid" "4502710" "name" "Stonewards" "StateFlags" "4" "installdir" "Stonewards" }"#.utf8)
            .write(to: steam.appendingPathComponent("steamapps/appmanifest_4502710.acf"))
        try Data(#"{"formatVersion":1,"steamAppId":4502710,"name":"Stonewards","status":"works","graphics":"dxmt"}"#.utf8)
            .write(to: profiles.appendingPathComponent("4502710.json"))
        var settings = AppSettings(dataDirectory: data)
        settings.wineBinary = "/nonexistent/wine"
        settings.profilesDirectory = profiles.path

        let gateway = try BarrelCoreGateway(settings: settings)

        #expect(try gateway.steamBottle() == "steam")
        let games = try gateway.games(in: "steam")
        #expect(games.map(\.name) == ["Stonewards"])
        #expect(games.first?.executable == "Stonewards.exe")
        #expect(games.first?.graphics == GameGraphics(backend: .dxmt, source: .profile))
        #expect(games.first?.profileStatus == .works)
    }

    @Test func noBottleWithSteamMeansNoSteamBottle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gateway-\(UUID().uuidString)")
        let store = try FileBottleStore(root: root)
        try store.save(Bottle(name: "steam", windowsVersion: .win10))
        var settings = AppSettings(dataDirectory: root)
        settings.wineBinary = "/nonexistent/wine"
        #expect(try BarrelCoreGateway(settings: settings).steamBottle() == nil)
    }
}
