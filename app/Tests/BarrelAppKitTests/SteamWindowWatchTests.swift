import BarrelCore
import Foundation
import Testing
@testable import BarrelAppKit

struct SteamWindowWatchTests {
    let start = Date(timeIntervalSince1970: 1_000)
    let helper = ScreenWindow(id: 1, ownerName: "wine", ownerPID: 50, layer: 0, width: 500, height: 500)
    let finder = ScreenWindow(id: 2, ownerName: "Finder", ownerPID: 10, layer: 0, width: 1400, height: 900)
    let steam = ScreenWindow(id: 3, ownerName: "wine", ownerPID: 51, layer: 0, width: 1280, height: 800)

    func watch(before: [ScreenWindow] = []) -> SteamWindowWatch {
        SteamWindowWatch(before: before, startedAt: start, timeout: 180)
    }

    @Test func waitsWhileOnlyWineHelperWindowsAreOnScreen() {
        let state = watch(before: [helper]).state(windows: [helper, finder], now: start + 40, launch: .running)
        #expect(state == .waiting)
    }

    @Test func aNewLargeWineWindowMeansSteamIsOpen() {
        let state = watch(before: [helper]).state(windows: [helper, steam], now: start + 40, launch: .running)
        #expect(state == .ready)
    }

    @Test func menusAndOverlaysAreNotSteamsWindow() {
        var menu = steam
        menu.layer = 101
        #expect(watch().state(windows: [menu], now: start + 5, launch: .running) == .waiting)
    }

    @Test func aBigWindowFromAnotherAppIsNotSteam() {
        #expect(watch().state(windows: [finder], now: start + 5, launch: .running) == .waiting)
    }

    @Test func aWindowThatWasAlreadyOpenDoesNotCountWhileSteamStarts() {
        #expect(watch(before: [steam]).state(windows: [steam], now: start + 5, launch: .running) == .waiting)
    }

    @Test func steamAlreadyOpenIsReadyOnceTheLaunchHandsOff() {
        // A second steam.exe passes the request to the running Steam and exits at once.
        #expect(watch(before: [steam]).state(windows: [steam], now: start + 2, launch: .exited(0)) == .ready)
    }

    @Test func aCleanExitWithoutAWindowKeepsWaiting() {
        // Steam's updater exits and starts Steam again.
        #expect(watch().state(windows: [helper], now: start + 30, launch: .exited(0)) == .waiting)
    }

    @Test func aFailedExitWithoutAWindowFails() {
        #expect(watch().state(windows: [helper], now: start + 30, launch: .exited(3)) == .failed(exitCode: 3))
    }

    @Test func givesUpAfterTheTimeout() {
        #expect(watch().state(windows: [helper], now: start + 180, launch: .running) == .timedOut)
        #expect(watch().state(windows: [helper], now: start + 179, launch: .running) == .waiting)
    }

    @Test func theWindowWinsOverTheTimeout() {
        #expect(watch().state(windows: [steam], now: start + 200, launch: .running) == .ready)
    }
}

/// Window lists handed out one per poll; the last one repeats.
final class FakeWindowSource: WindowSource, @unchecked Sendable {
    private var snapshots: [[ScreenWindow]]

    init(_ snapshots: [[ScreenWindow]]) { self.snapshots = snapshots }

    func onScreenWindows() -> [ScreenWindow] {
        snapshots.count > 1 ? snapshots.removeFirst() : snapshots.first ?? []
    }
}

@MainActor
struct OpenSteamTests {
    let steam = ScreenWindow(id: 3, ownerName: "wine", ownerPID: 51, layer: 0, width: 1280, height: 800)

    func model(_ gateway: FakeGateway, windows: [[ScreenWindow]]) -> BottleListViewModel {
        gateway.steam = "steam"
        let model = BottleListViewModel(gateway: gateway, windows: FakeWindowSource(windows),
                                        steamPollInterval: .milliseconds(1))
        return model
    }

    @Test func openingSteamWaitsUntilItsWindowIsOnScreen() async {
        let gateway = FakeGateway()
        gateway.steamExit = nil  // Steam keeps running
        let model = model(gateway, windows: [[], [], [], [steam]])
        await model.loadLibrary()

        let opening = Task { await model.openSteam() }
        await Task.yield()
        #expect(model.isOpeningSteam)
        await opening.value

        #expect(!model.isOpeningSteam)
        #expect(model.errorMessage == nil)
        #expect(gateway.steamOpens == ["steam"])
    }

    @Test func steamQuittingWithAnErrorBeforeItsWindowSaysSo() async {
        let gateway = FakeGateway()
        gateway.steamExit = 3
        let model = model(gateway, windows: [[]])
        await model.loadLibrary()

        await model.openSteam()

        #expect(!model.isOpeningSteam)
        #expect(model.errorMessage == "Steam closed before its window appeared (exit code 3).")
    }
}
