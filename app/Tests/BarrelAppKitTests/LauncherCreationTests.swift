import BarrelCore
import Foundation
import Testing
@testable import BarrelAppKit

@MainActor
struct LauncherViewModelTests {
    let stonewards = GameSummary(appID: 4502710, name: "Stonewards", executable: "Stonewards.exe",
                                 executablePath: nil, graphics: GameGraphics(backend: .dxvk, source: .profile),
                                 profileStatus: .works)

    @Test func createLauncherRecordsTheNewApp() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "steam", windowsVersion: .win10)])
        let model = BottleListViewModel(gateway: gateway)
        await model.createLauncher(name: "Game", program: URL(fileURLWithPath: "/p/Game.exe"), in: "steam")
        #expect(gateway.launchers.map(\.name) == ["Game"])
        #expect(gateway.launchers.map(\.program) == ["/p/Game.exe"])
        #expect(model.lastLauncher?.lastPathComponent == "Game.app")
        #expect(model.errorMessage == nil)
    }

    @Test func addingAGameToTheDockShowsItIsInTheDock() async {
        let gateway = FakeGateway()
        gateway.steam = "steam"
        gateway.gameList = [stonewards]
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()
        #expect(model.games.map(\.isInDock) == [false])

        await model.addToDock(stonewards)

        #expect(gateway.gameLaunchers.map(\.name) == ["Stonewards"])
        #expect(model.games.map(\.isInDock) == [true])
        #expect(model.lastLauncher == nil)  // Adding a game to the Dock does not open Finder
    }

    @Test func removingAGameFromTheDockBringsBackAddToDock() async {
        let gateway = FakeGateway()
        gateway.steam = "steam"
        var game = stonewards
        game.isInDock = true
        gateway.gameList = [game]
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()

        await model.removeFromDock(game)

        #expect(gateway.removedGameLaunchers == ["Stonewards"])
        #expect(model.games.map(\.isInDock) == [false])
        #expect(model.errorMessage == nil)
    }

    @Test func aFailedReloadAfterAddingStillShowsTheGameInTheDock() async {
        let gateway = FakeGateway()
        gateway.steam = "steam"
        gateway.gameList = [stonewards]
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()
        gateway.gamesFailure = BottleError.notFound("steam")

        await model.addToDock(stonewards)

        #expect(model.games.map(\.isInDock) == [true])
        #expect(model.lastLauncher == nil)  // Adding a game to the Dock does not open Finder
        #expect(model.errorMessage == BottleError.notFound("steam").description)
    }

    @Test func aFailedReloadAfterRemovingStillOffersAddToDock() async {
        let gateway = FakeGateway()
        gateway.steam = "steam"
        var game = stonewards
        game.isInDock = true
        gateway.gameList = [game]
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()
        gateway.gamesFailure = BottleError.notFound("steam")

        await model.removeFromDock(game)

        #expect(model.games.map(\.isInDock) == [false])
    }

    @Test func aFailureAfterTheAppWasTrashedStillRefreshesTheCard() async {
        let gateway = FakeGateway()
        gateway.steam = "steam"
        var game = stonewards
        game.isInDock = true
        gateway.gameList = [game]
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()
        gateway.failureAfterLauncherChange = DockError.notSaved

        await model.removeFromDock(game)

        #expect(gateway.removedGameLaunchers == ["Stonewards"])
        #expect(model.games.map(\.isInDock) == [false])
        #expect(model.errorMessage == DockError.notSaved.description)
    }

    @Test func launcherFailureShowsItsDescription() async {
        let gateway = FakeGateway()
        gateway.failure = LauncherError.invalidName(".x")
        let model = BottleListViewModel(gateway: gateway)
        await model.createLauncher(name: ".x", program: URL(fileURLWithPath: "/p/a.exe"), in: "steam")
        #expect(model.errorMessage == LauncherError.invalidName(".x").description)
        #expect(model.lastLauncher == nil)
    }
}

struct BarrelCoreGatewayLauncherTests {
    func settings(_ root: URL) -> AppSettings {
        var settings = AppSettings(dataDirectory: root.appendingPathComponent("data"))
        settings.wineBinary = "/rt/wine/bin/wine"
        settings.librariesDirectory = "/rt/deps/lib"
        settings.dxvkDirectory = "/rt/dxvk"
        return settings
    }

    @Test func launchersNeedTheBundledCommandLineTool() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString)")
        let gateway = try BarrelCoreGateway(settings: settings(root), barrelExecutable: nil, dock: Dock(store: MemoryDockStore()),
                                            launchersDirectory: root.appendingPathComponent("Apps"))
        #expect(throws: GatewayError.launchersNeedBarrelApp) {
            try gateway.createLauncher(name: "Game", bottle: "steam", program: "/p/Game.exe")
        }
    }

    /// A bottle named "steam" with Stonewards and Nightfall installed.
    func steamBottle(_ root: URL, games: [(Int, String)] = [(4502710, "Stonewards"), (100, "Nightfall")]) throws -> AppSettings {
        let data = root.appendingPathComponent("data")
        let store = try FileBottleStore(root: data)
        try store.save(Bottle(name: "steam", windowsVersion: .win10))
        let steam = SteamLibrary.steamDirectory(prefix: store.prefixURL(for: "steam"))
        try FileManager.default.createDirectory(at: steam.appendingPathComponent("steamapps"), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: steam.appendingPathComponent("steam.exe"))
        for (appID, name) in games {
            let game = steam.appendingPathComponent("steamapps/common/\(name)")
            try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
            try Data("MZ".utf8).write(to: game.appendingPathComponent("\(name).exe"))
            try Data(#""AppState" { "appid" "\#(appID)" "name" "\#(name)" "StateFlags" "4" "installdir" "\#(name)" }"#.utf8)
                .write(to: steam.appendingPathComponent("steamapps/appmanifest_\(appID).acf"))
        }
        return settings(root)
    }

    @Test func gamesPinnedInTheDockLoadAsInTheDock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString)")
        let apps = root.appendingPathComponent("Apps")
        let store = MemoryDockStore(), dock = Dock(store: store)
        let gateway = try BarrelCoreGateway(settings: steamBottle(root),
                                            barrelExecutable: URL(fileURLWithPath: "/opt/barrel"), dock: dock,
                                            launchersDirectory: apps)
        let app = try gateway.createGameLauncher(appID: 4502710, name: "Stonewards", bottle: "steam")
        _ = try gateway.createGameLauncher(appID: 4502710, name: "Stonewards", bottle: "steam")

        let games = try gateway.games(in: "steam")

        #expect(store.apps.count == 1)
        #expect(dock.contains(app))

        #expect(games.first { $0.name == "Stonewards" }?.isInDock == true)
        #expect(games.first { $0.name == "Nightfall" }?.isInDock == false)
    }

    @Test func aGameWhoseAppIsNotInTheDockLoadsAsNotInTheDock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString)")
        let apps = root.appendingPathComponent("Apps")
        let store = MemoryDockStore(), dock = Dock(store: store)
        let gateway = try BarrelCoreGateway(settings: steamBottle(root),
                                            barrelExecutable: URL(fileURLWithPath: "/opt/barrel"), dock: dock,
                                            launchersDirectory: apps)
        let app = try gateway.createGameLauncher(appID: 4502710, name: "Stonewards", bottle: "steam")
        try dock.remove(app)

        #expect(FileManager.default.fileExists(atPath: app.path))
        #expect(try gateway.games(in: "steam").first { $0.name == "Stonewards" }?.isInDock == false)

        _ = try gateway.createGameLauncher(appID: 4502710, name: "Stonewards", bottle: "steam")

        #expect(store.apps.count == 1)
        #expect(try gateway.games(in: "steam").first { $0.name == "Stonewards" }?.isInDock == true)
    }

    @Test func removingAGameWhoseAppIsAlreadyGoneStillRemovesItsTile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString)")
        let apps = root.appendingPathComponent("Apps")
        let store = MemoryDockStore(), dock = Dock(store: store)
        let gateway = try BarrelCoreGateway(settings: steamBottle(root),
                                            barrelExecutable: URL(fileURLWithPath: "/opt/barrel"), dock: dock,
                                            launchersDirectory: apps) { _ in Issue.record("nothing to trash") }
        let app = try gateway.createGameLauncher(appID: 4502710, name: "Stonewards", bottle: "steam")
        try FileManager.default.removeItem(at: app)

        try gateway.removeGameLauncher(name: "Stonewards")

        #expect(store.apps.isEmpty)
        #expect(try gateway.games(in: "steam").first { $0.name == "Stonewards" }?.isInDock == false)
    }

    @Test func removingAGameLauncherMovesItToTheTrash() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString)")
        let apps = root.appendingPathComponent("Apps"), trash = root.appendingPathComponent("Trash")
        let store = MemoryDockStore(), dock = Dock(store: store)
        let gateway = try BarrelCoreGateway(settings: steamBottle(root),
                                            barrelExecutable: URL(fileURLWithPath: "/opt/barrel"), dock: dock,
                                            launchersDirectory: apps) {
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent))
        }
        let app = try gateway.createGameLauncher(appID: 4502710, name: "Stonewards", bottle: "steam")

        #expect(store.apps.count == 1)

        try gateway.removeGameLauncher(name: "Stonewards")

        #expect(store.apps.isEmpty)
        #expect(try gateway.games(in: "steam").first { $0.name == "Stonewards" }?.isInDock == false)
        #expect(!FileManager.default.fileExists(atPath: app.path))
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Stonewards.app").path))
    }

    @Test func aGameWithAColonInItsNameGoesToTheDockAndBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString)")
        let apps = root.appendingPathComponent("Apps"), trash = root.appendingPathComponent("Trash")
        let store = MemoryDockStore(), dock = Dock(store: store)
        let title = "Age of Empires II: Definitive Edition"
        let gateway = try BarrelCoreGateway(settings: steamBottle(root, games: [(813780, title)]),
                                            barrelExecutable: URL(fileURLWithPath: "/opt/barrel"), dock: dock,
                                            launchersDirectory: apps) {
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent))
        }

        let app = try gateway.createGameLauncher(appID: 813780, name: title, bottle: "steam")

        #expect(app.lastPathComponent == "Age of Empires II - Definitive Edition.app")
        #expect(try gateway.games(in: "steam").map(\.isInDock) == [true])
        #expect(try gateway.games(in: "steam").map(\.name) == [title])
        let plist = try #require(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")))
        #expect(plist["CFBundleDisplayName"] as? String == title)

        #expect(store.apps.count == 1)

        try gateway.removeGameLauncher(name: title)

        #expect(store.apps.isEmpty)
        #expect(try gateway.games(in: "steam").map(\.isInDock) == [false])
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent(app.lastPathComponent).path))
    }

    @Test func launcherRunsTheBundledToolWithTheAppSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString)")
        let gateway = try BarrelCoreGateway(settings: settings(root),
                                            barrelExecutable: URL(fileURLWithPath: "/Applications/Barrel.app/Contents/MacOS/barrel"),
                                            dock: Dock(store: MemoryDockStore()),
                                            launchersDirectory: root.appendingPathComponent("Apps"))
        let app = try gateway.createLauncher(name: "Game", bottle: "steam", program: "/p/Game.exe")
        let script = try String(contentsOf: app.appendingPathComponent("Contents/MacOS/launcher"), encoding: .utf8)
        #expect(script.contains("export BARREL_HOME='\(root.appendingPathComponent("data").path)'"))
        #expect(script.contains("export BARREL_WINE='/rt/wine/bin/wine'"))
        #expect(script.contains("export BARREL_LIBS='/rt/deps/lib'"))
        #expect(script.contains("export BARREL_DXVK='/rt/dxvk'"))
        #expect(!script.contains("BARREL_DXMT"))
        #expect(script.contains("exec '/Applications/Barrel.app/Contents/MacOS/barrel' 'run' '--bottle' 'steam' '/p/Game.exe'"))
    }
}
