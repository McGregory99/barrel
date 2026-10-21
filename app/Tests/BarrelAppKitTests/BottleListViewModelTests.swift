import BarrelCore
import Foundation
import Testing
@testable import BarrelAppKit

@MainActor
struct BottleListViewModelTests {
    private func makeModel(_ gateway: FakeGateway) -> BottleListViewModel {
        BottleListViewModel(gateway: gateway)
    }

    @Test func loadPopulatesBottlesAndDefaultMarker() async {
        let gateway = FakeGateway(
            bottles: [Bottle(name: "a", windowsVersion: .win10), Bottle(name: "b", windowsVersion: .win7)],
            defaultName: "b")
        let model = makeModel(gateway)
        await model.load()
        #expect(model.bottles.map(\.name) == ["a", "b"])
        #expect(model.isDefault(model.bottles[1]))
        #expect(!model.isDefault(model.bottles[0]))
        #expect(model.errorMessage == nil)
    }

    @Test func createAddsAndSelectsBottle() async {
        let model = makeModel(FakeGateway())
        await model.create(name: "games", version: .win11, description: "x")
        #expect(model.bottles.map(\.name) == ["games"])
        #expect(model.selection == "games")
        #expect(model.errorMessage == nil)
        #expect(!model.isBusy)
    }

    @Test func createFailureSetsErrorMessageFromDescription() async {
        let gateway = FakeGateway()
        gateway.failure = BottleError.alreadyExists("games")
        let model = makeModel(gateway)
        await model.create(name: "games", version: .win10, description: nil)
        #expect(model.errorMessage == "Bottle 'games' already exists")
        #expect(model.bottles.isEmpty)
        #expect(!model.isBusy)
    }

    @Test func unavailableBackendSetsError() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "a", windowsVersion: .win10)])
        let model = makeModel(gateway)
        await model.load()
        await model.setGraphics("a", backend: .dxvk)
        #expect(model.errorMessage == BottleError.backendUnavailable(.dxvk).description)
        #expect(model.bottles[0].graphicsBackend == .wined3d)
        #expect(!model.isAvailable(.dxvk))
        #expect(model.isAvailable(.wined3d))
    }

    @Test func availableBackendIsApplied() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "a", windowsVersion: .win10)])
        gateway.unavailable = []
        let model = makeModel(gateway)
        await model.load()
        await model.setGraphics("a", backend: .dxmt)
        #expect(model.bottles[0].graphicsBackend == .dxmt)
        #expect(model.errorMessage == nil)
    }

    @Test func deleteClearsSelectionAndDefault() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "a", windowsVersion: .win10)], defaultName: "a")
        let model = makeModel(gateway)
        await model.load()
        model.selection = "a"
        await model.delete("a")
        #expect(model.bottles.isEmpty)
        #expect(model.selection == nil)
        #expect(model.defaultName == nil)
    }

    @Test func setDefaultMovesMarker() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "a", windowsVersion: .win10),
                                            Bottle(name: "b", windowsVersion: .win10)], defaultName: "a")
        let model = makeModel(gateway)
        await model.load()
        await model.setDefault("b")
        #expect(model.defaultName == "b")
    }

    @Test func msyncToggleIsPersistedAndReloaded() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "a", windowsVersion: .win10)])
        let model = makeModel(gateway)
        await model.load()
        await model.setMSync("a", enabled: false)
        #expect(model.bottles[0].msync == false)
    }

    @Test func copyAddsBottleAndSelectsIt() async {
        let model = makeModel(FakeGateway(bottles: [Bottle(name: "a", windowsVersion: .win10)]))
        await model.load()
        await model.copy("a", to: "a2")
        #expect(model.bottles.map(\.name).sorted() == ["a", "a2"])
        #expect(model.selection == "a2")
    }

    @Test func restoreAddsBottleAndSelectsIt() async {
        let model = makeModel(FakeGateway())
        await model.restore(from: URL(fileURLWithPath: "/x.tar.gz"), as: "back")
        #expect(model.selection == "back")
        #expect(model.bottles.map(\.name) == ["back"])
    }

    @Test func runForwardsPathToBottle() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "a", windowsVersion: .win10)])
        let model = makeModel(gateway)
        await model.run(URL(fileURLWithPath: "/setup.exe"), in: "a")
        #expect(gateway.runs.first?.path == "/setup.exe")
        #expect(gateway.runs.first?.bottle == "a")
    }

    @Test func exportFailureSurfacesWineErrorDescription() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "a", windowsVersion: .win10)])
        gateway.failure = WineRuntimeError.commandFailed(command: "tar", status: 2)
        let model = makeModel(gateway)
        await model.export("a", to: URL(fileURLWithPath: "/x.tar.gz"))
        #expect(model.errorMessage == "'tar' exited with status 2")
    }

    @Test func dismissErrorClearsMessage() async {
        let gateway = FakeGateway()
        gateway.failure = BottleError.noDefaultBottle
        let model = makeModel(gateway)
        await model.load()
        #expect(model.errorMessage != nil)
        model.dismissError()
        #expect(model.errorMessage == nil)
    }
}
