import BarrelCore
import Foundation
import Testing
@testable import BarrelAppKit

@MainActor
struct LibraryTests {
    let stonewards = GameSummary(appID: 4502710, name: "Stonewards", executable: "Stonewards.exe",
                                 executablePath: nil, graphics: GameGraphics(backend: .dxvk, source: .profile),
                                 profileStatus: .works)

    @Test func withoutSteamTheLibraryOffersToInstallIt() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "Office", windowsVersion: .win10)])
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()
        #expect(model.steamBottle == nil)
        #expect(model.games.isEmpty)
    }

    @Test func installingSteamUsesItsOwnBottleAndShowsTheLibrary() async {
        let gateway = FakeGateway()
        gateway.gameList = [stonewards]
        let model = BottleListViewModel(gateway: gateway)

        await model.installSteam()

        #expect(gateway.installs.map(\.recipe) == ["steam"])
        #expect(gateway.installs.map(\.bottle) == [nil])
        #expect(model.steamBottle == "steam")
        #expect(model.games == [stonewards])
        #expect(model.bottles.map(\.name) == ["steam"])
    }

    @Test func playingAGameGoesThroughItsBottle() async {
        let gateway = FakeGateway()
        gateway.steam = "steam"
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()

        await model.play(stonewards)

        #expect(gateway.plays.map(\.appID) == [4502710])
        #expect(gateway.plays.map(\.bottle) == ["steam"])
    }

    @Test func choosingAGamesGraphicsRecordsThePlayersChoice() async {
        let gateway = FakeGateway()
        gateway.steam = "steam"
        gateway.gameList = [stonewards]
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()

        await model.setGraphics(for: stonewards, backend: .dxmt)

        #expect(gateway.gameGraphicsChanges.map(\.executable) == ["Stonewards.exe"])
        #expect(model.games.first?.graphics == GameGraphics(backend: .dxmt, source: .player))
    }

    @Test func automaticGraphicsHandsTheGameBackToItsProfile() async {
        let gateway = FakeGateway()
        gateway.steam = "steam"
        gateway.gameList = [stonewards]
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()
        await model.setGraphics(for: stonewards, backend: .dxmt)

        await model.setAutomaticGraphics(for: stonewards)

        #expect(gateway.gameGraphicsResets == ["Stonewards.exe"])
        #expect(model.games.first?.graphics.source == .profile)
    }

    @Test func addingAGameToTheDockCreatesAGameLauncher() async {
        let gateway = FakeGateway()
        gateway.steam = "steam"
        let model = BottleListViewModel(gateway: gateway)
        await model.loadLibrary()

        await model.addToDock(stonewards)

        #expect(gateway.gameLaunchers.map(\.appID) == [4502710])
        #expect(gateway.gameLaunchers.map(\.name) == ["Stonewards"])
        #expect(model.lastLauncher?.lastPathComponent == "Stonewards.app")
    }

    @Test func aGameWithoutAKnownExecutableCannotChangeGraphics() async {
        var unknown = stonewards
        unknown.executable = nil
        #expect(!unknown.canChooseGraphics)
        #expect(stonewards.canChooseGraphics)
    }
}
