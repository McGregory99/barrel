import BarrelCore
import Foundation
import Testing
@testable import BarrelAppKit

@MainActor
struct LauncherViewModelTests {
    @Test func createLauncherRecordsTheNewApp() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "steam", windowsVersion: .win10)])
        let model = BottleListViewModel(gateway: gateway)
        await model.createLauncher(name: "Game", program: URL(fileURLWithPath: "/p/Game.exe"), in: "steam")
        #expect(gateway.launchers.map(\.name) == ["Game"])
        #expect(gateway.launchers.map(\.program) == ["/p/Game.exe"])
        #expect(model.lastLauncher?.lastPathComponent == "Game.app")
        #expect(model.errorMessage == nil)
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
        let gateway = try BarrelCoreGateway(settings: settings(root), barrelExecutable: nil,
                                            launchersDirectory: root.appendingPathComponent("Apps"))
        #expect(throws: GatewayError.launchersNeedBarrelApp) {
            try gateway.createLauncher(name: "Game", bottle: "steam", program: "/p/Game.exe")
        }
    }

    @Test func launcherRunsTheBundledToolWithTheAppSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gw-\(UUID().uuidString)")
        let gateway = try BarrelCoreGateway(settings: settings(root),
                                            barrelExecutable: URL(fileURLWithPath: "/Applications/Barrel.app/Contents/MacOS/barrel"),
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
