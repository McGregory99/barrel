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

    @Test func bottleBackendIsWrittenAsGlobalDllOverrides() throws {
        let f = try GraphicsFixture()
        _ = try f.service.create(name: "Game", version: .win10)
        try f.service.setGraphics("Game", backend: .dxvk)
        let writes = f.base.runtime.registryWrites()
        for dll in ["d3d9", "d3d10core", "d3d11", "dxgi"] {
            #expect(writes["HKCU\\Software\\Wine\\DllOverrides\\\(dll)"] == "native,builtin")
        }

        try f.service.setGraphics("Game", backend: .wined3d)
        #expect(f.base.runtime.registryWrites()["HKCU\\Software\\Wine\\DllOverrides\\d3d11"] == "builtin")
    }

    @Test func appBackendIsWrittenToAppDefaultsAndPersisted() throws {
        let f = try GraphicsFixture()
        _ = try f.service.create(name: "Steam", version: .win10)
        try f.service.setGraphics("Steam", backend: .dxvk)
        try f.service.setAppGraphics("Steam", executable: "steamwebhelper.exe", backend: .wined3d)

        let writes = f.base.runtime.registryWrites()
        let key = "HKCU\\Software\\Wine\\AppDefaults\\steamwebhelper.exe\\DllOverrides"
        for dll in ["d3d9", "d3d10core", "d3d11", "dxgi"] {
            #expect(writes["\(key)\\\(dll)"] == "builtin")
        }
        let bottle = try f.base.store.load("Steam")
        #expect(bottle.graphicsBackend == .dxvk)
        #expect(bottle.appGraphics == ["steamwebhelper.exe": .wined3d])
    }

    @Test func appBackendInstallsReplacementDlls() throws {
        let f = try GraphicsFixture()
        _ = try f.service.create(name: "Mixed", version: .win10)
        try f.service.setAppGraphics("Mixed", executable: "Game.exe", backend: .dxvk)
        #expect(f.installer.installed.map(\.0) == [.dxvk])
    }

    @Test func everyWineCommandUsesTheBottlesSyncMode() throws {
        let f = try GraphicsFixture()
        _ = try f.service.create(name: "Steam", version: .win10)
        try f.service.setGraphics("Steam", backend: .dxvk)
        try f.service.setAppGraphics("Steam", executable: "steamwebhelper.exe", backend: .wined3d)
        #expect(!f.base.runtime.environments.isEmpty)
        #expect(f.base.runtime.environments.allSatisfy { $0["WINEMSYNC"] == "1" })

        try f.service.setMSync("Steam", enabled: false)
        try f.service.setGraphics("Steam", backend: .wined3d)
        #expect(f.base.runtime.environments.last?["WINEMSYNC"] == nil)
    }

    @Test func d3dmetalCannotBeSetPerApp() throws {
        let f = try GraphicsFixture()
        _ = try f.service.create(name: "B", version: .win10)
        #expect(throws: BottleError.backendNotPerApp(.d3dmetal)) {
            try f.service.setAppGraphics("B", executable: "Game.exe", backend: .d3dmetal)
        }
    }

    @Test(arguments: ["", "dir\\Game.exe", "a/b.exe"])
    func appBackendRejectsInvalidExecutableNames(executable: String) throws {
        let f = try GraphicsFixture()
        _ = try f.service.create(name: "B", version: .win10)
        #expect(throws: BottleError.invalidExecutable(executable)) {
            try f.service.setAppGraphics("B", executable: executable, backend: .wined3d)
        }
    }

    @Test func metadataWithoutAppGraphicsDecodesEmpty() throws {
        let json = #"{"name":"Old","uuid":"\#(UUID().uuidString)","windowsVersion":"win7","createdAt":"2026-01-01T00:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Bottle.self, from: Data(json.utf8)).appGraphics.isEmpty)
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

    @Test func wined3dEnvironmentLeavesDllChoiceToTheRegistry() {
        let env = LaunchEnvironment.make(for: bottle(.wined3d), components: components)
        #expect(env["WINEDLLOVERRIDES"] == nil)
        #expect(env["CX_ACTIVE_GRAPHICS_BACKEND"] == "wined3d")
        #expect(env["WINEMSYNC"] == "1")
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"] == "/rt/lib:/usr/local/lib:/usr/lib")
    }

    @Test func dxvkEnvironmentNamesTheBackendOnly() {
        let env = LaunchEnvironment.make(for: bottle(.dxvk), components: components)
        #expect(env["WINEDLLOVERRIDES"] == nil)
        #expect(env["CX_ACTIVE_GRAPHICS_BACKEND"] == "dxvk")
    }

    @Test func d3dmetalAddsToolkitPaths() {
        let env = LaunchEnvironment.make(for: bottle(.d3dmetal), components: components)
        #expect(env["CX_ACTIVE_GRAPHICS_BACKEND"] == "d3dmetal")
        #expect(env["WINEDLLPATH"] == "/gptk/wine")
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"] == "/rt/lib:/gptk/external:/usr/local/lib:/usr/lib")
        #expect(env["DYLD_FALLBACK_FRAMEWORK_PATH"] == "/gptk/external")
    }

    @Test(arguments: GraphicsBackend.allCases)
    func moltenVKArgumentBuffersAreDisabled(backend: GraphicsBackend) {
        let env = LaunchEnvironment.make(for: bottle(backend), components: components)
        #expect(env["MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS"] == "0")
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

@Suite struct FileGraphicsInstallerTests {
    func makeTree(_ root: URL, _ files: [String]) throws {
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.utf8).write(to: url)
        }
    }

    func dlls(_ directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    @Test func dxvkCopiesX64AndX32Folders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gfx-\(UUID().uuidString)")
        try makeTree(root.appendingPathComponent("dxvk"), ["x64/d3d11.dll", "x64/dxgi.dll", "x32/d3d11.dll", "x64/README"])
        let prefix = root.appendingPathComponent("prefix")
        try FileGraphicsInstaller().install(.dxvk, into: prefix,
                                            components: RuntimeComponents(dxvkDirectory: root.appendingPathComponent("dxvk")))
        #expect(dlls(prefix.appendingPathComponent("drive_c/windows/system32")) == ["d3d11.dll", "dxgi.dll"])
        #expect(dlls(prefix.appendingPathComponent("drive_c/windows/syswow64")) == ["d3d11.dll"])
    }

    @Test func dxmtCopiesItsSystem32AndSyswow64Folders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gfx-\(UUID().uuidString)")
        try makeTree(root.appendingPathComponent("dxmt"), ["system32/d3d11.dll", "syswow64/dxgi.dll",
                                                           "x86_64-windows/winemetal.dll"])
        let prefix = root.appendingPathComponent("prefix")
        try FileGraphicsInstaller().install(.dxmt, into: prefix,
                                            components: RuntimeComponents(dxmtDirectory: root.appendingPathComponent("dxmt")))
        #expect(dlls(prefix.appendingPathComponent("drive_c/windows/system32")) == ["d3d11.dll"])
        #expect(dlls(prefix.appendingPathComponent("drive_c/windows/syswow64")) == ["dxgi.dll"])
    }
}

@Suite struct DXMTEnvironmentTests {
    let components = RuntimeComponents(dxvkDirectory: URL(fileURLWithPath: "/rt/dxvk"),
                                       dxmtDirectory: URL(fileURLWithPath: "/rt/dxmt"),
                                       gptkDirectory: URL(fileURLWithPath: "/gptk"))

    func bottle(_ backend: GraphicsBackend, apps: [String: GraphicsBackend] = [:]) -> Bottle {
        var bottle = Bottle(name: "B", windowsVersion: .win10)
        bottle.graphicsBackend = backend
        bottle.appGraphics = apps
        return bottle
    }

    @Test func dxmtBottleFindsWinemetalThroughWineDllPath() {
        #expect(LaunchEnvironment.make(for: bottle(.dxmt), components: components)["WINEDLLPATH"] == "/rt/dxmt")
    }

    @Test func perAppDxmtAlsoAddsWinemetal() {
        let env = LaunchEnvironment.make(for: bottle(.dxvk, apps: ["Game.exe": .dxmt]), components: components)
        #expect(env["WINEDLLPATH"] == "/rt/dxmt")
    }

    @Test func bottlesWithoutDxmtDoNotChangeWineDllPath() {
        let env = LaunchEnvironment.make(for: bottle(.dxvk, apps: ["steamwebhelper.exe": .wined3d]), components: components)
        #expect(env["WINEDLLPATH"] == nil)
    }

    @Test func d3dmetalAndDxmtPathsAreCombined() {
        let env = LaunchEnvironment.make(for: bottle(.d3dmetal, apps: ["Game.exe": .dxmt]), components: components)
        #expect(env["WINEDLLPATH"] == "/gptk/wine:/rt/dxmt")
    }
}
