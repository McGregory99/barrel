import Foundation
import Testing
@testable import BarrelCore

final class FakeGraphicsInstaller: GraphicsInstaller {
    var installed: [(GraphicsBackend, String)] = []

    func install(_ backend: GraphicsBackend, into prefix: URL, components: RuntimeComponents) throws {
        installed.append((backend, prefix.lastPathComponent))
    }
}

struct GraphicsFixture {
    let base: Fixture
    let installer = FakeGraphicsInstaller()
    let service: BottleService

    init(components: RuntimeComponents = RuntimeComponents(
        libraryDirectory: URL(fileURLWithPath: "/rt/lib"),
        dxvkDirectory: URL(fileURLWithPath: "/rt/dxvk"))) throws {
        base = try Fixture()
        service = BottleService(store: base.store, runtime: base.runtime,
                                graphics: installer, components: components)
    }
}

@Suite struct GraphicsBackendTests {
    @Test func newBottlesUseWined3dAndMSync() throws {
        let f = try GraphicsFixture()
        let bottle = try f.service.create(name: "B", version: .win10)
        #expect(bottle.graphicsBackend == .wined3d)
        #expect(bottle.msync)
    }

    @Test func metadataWithoutGraphicsFieldsDecodesWithDefaults() throws {
        let json = #"{"name":"Old","uuid":"\#(UUID().uuidString)","windowsVersion":"win7","createdAt":"2026-01-01T00:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bottle = try decoder.decode(Bottle.self, from: Data(json.utf8))
        #expect(bottle.graphicsBackend == .wined3d)
        #expect(bottle.msync)
    }

    @Test func switchingToDXVKInstallsItAndPersists() throws {
        let f = try GraphicsFixture()
        _ = try f.service.create(name: "Game", version: .win10)
        try f.service.setGraphics("Game", backend: .dxvk)

        #expect(try f.base.store.load("Game").graphicsBackend == .dxvk)
        #expect(f.installer.installed.map(\.0) == [.dxvk])
        #expect(f.installer.installed.map(\.1) == ["Game"])
    }

    @Test func switchingToUnavailableBackendFailsAndKeepsSetting() throws {
        let f = try GraphicsFixture(components: RuntimeComponents())
        _ = try f.service.create(name: "Game", version: .win10)
        #expect(throws: BottleError.backendUnavailable(.dxvk)) {
            try f.service.setGraphics("Game", backend: .dxvk)
        }
        #expect(try f.base.store.load("Game").graphicsBackend == .wined3d)
        #expect(f.installer.installed.isEmpty)
    }

    @Test func parsesBackendNames() throws {
        #expect(try GraphicsBackend(name: "DXVK") == .dxvk)
        #expect(throws: BottleError.unknownBackend("vulkan")) { try GraphicsBackend(name: "vulkan") }
    }
}

@Suite struct LaunchEnvironmentTests {
    let components = RuntimeComponents(
        libraryDirectory: URL(fileURLWithPath: "/rt/lib"),
        dxvkDirectory: URL(fileURLWithPath: "/rt/dxvk"),
        gptkDirectory: URL(fileURLWithPath: "/gptk"))

    func bottle(_ backend: GraphicsBackend, msync: Bool = true) -> Bottle {
        var bottle = Bottle(name: "B", windowsVersion: .win10)
        bottle.graphicsBackend = backend
        bottle.msync = msync
        return bottle
    }

    @Test func wined3dForcesBuiltinDirect3D() {
        let env = LaunchEnvironment.make(for: bottle(.wined3d), components: components)
        #expect(env["WINEDLLOVERRIDES"] == "d3d9,d3d10core,d3d11,dxgi=b")
        #expect(env["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d")
        #expect(env["WINEMSYNC"] == "1")
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"] == "/rt/lib:/usr/local/lib:/usr/lib")
    }

    @Test func dxvkPrefersNativeDirect3D() {
        let env = LaunchEnvironment.make(for: bottle(.dxvk), components: components)
        #expect(env["WINEDLLOVERRIDES"] == "d3d9,d3d10core,d3d11,dxgi=n,b")
        #expect(env["CX_ACTIVE_GRAPHICS_BACKEND"] == "dxvk")
    }

    @Test func d3dmetalAddsToolkitPaths() {
        let env = LaunchEnvironment.make(for: bottle(.d3dmetal), components: components)
        #expect(env["CX_ACTIVE_GRAPHICS_BACKEND"] == "d3dmetal")
        #expect(env["WINEDLLPATH"] == "/gptk/wine")
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"] == "/rt/lib:/gptk/external:/usr/local/lib:/usr/lib")
        #expect(env["DYLD_FALLBACK_FRAMEWORK_PATH"] == "/gptk/external")
    }

    @Test func msyncCanBeDisabled() {
        let env = LaunchEnvironment.make(for: bottle(.wined3d, msync: false), components: components)
        #expect(env["WINEMSYNC"] == nil)
    }

    @Test func mergesCallerDllOverridesInsteadOfReplacingThem() {
        let merged = LaunchEnvironment.merge(
            ["WINEDLLOVERRIDES": "d3d9,d3d10core,d3d11,dxgi=b", "WINEMSYNC": "1"],
            into: ["WINEDLLOVERRIDES": "mscoree,mshtml=", "HOME": "/Users/x"])
        #expect(merged["WINEDLLOVERRIDES"] == "mscoree,mshtml=;d3d9,d3d10core,d3d11,dxgi=b")
        #expect(merged["WINEMSYNC"] == "1")
        #expect(merged["HOME"] == "/Users/x")
    }

    @Test func mergeUsesBottleOverridesWhenCallerHasNone() {
        let merged = LaunchEnvironment.merge(["WINEDLLOVERRIDES": "dxgi=n,b"], into: ["HOME": "/Users/x"])
        #expect(merged["WINEDLLOVERRIDES"] == "dxgi=n,b")
    }

    @Test func runPassesBottleEnvironmentToWine() throws {
        let f = try GraphicsFixture()
        _ = try f.service.create(name: "Game", version: .win10)
        try f.service.setGraphics("Game", backend: .dxvk)
        _ = try f.service.run("/tmp/game.exe", arguments: [], bottle: "Game")
        #expect(f.base.runtime.lastEnvironment["CX_ACTIVE_GRAPHICS_BACKEND"] == "dxvk")
    }
}
