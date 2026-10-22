import Foundation
import Testing
@testable import BarrelCore

func profileJSON(_ fields: String = "") -> Data {
    Data(#"{"formatVersion":1,"steamAppId":4502710,"name":"Stonewards","status":"works"\#(fields)}"#.utf8)
}

@Suite struct GameProfileParserTests {
    @Test func parsesEveryField() throws {
        let profile = try GameProfileParser.parse(profileJSON(#"""
            ,"executable":"Stonewards.exe","graphics":"dxmt","dllOverrides":{"xinput1_3":"native,builtin"},
            "launchArguments":["-dx11"],"notes":"Menu tested on an M2."
            """#))
        #expect(profile == GameProfile(steamAppID: 4502710, name: "Stonewards", status: .works,
                                       executable: "Stonewards.exe", graphics: .dxmt,
                                       dllOverrides: ["xinput1_3": "native,builtin"], launchArguments: ["-dx11"],
                                       notes: "Menu tested on an M2."))
    }

    @Test func onlyIdNameAndStatusAreRequired() throws {
        let profile = try GameProfileParser.parse(profileJSON())
        #expect(profile.graphics == nil && profile.executable == nil && profile.dllOverrides.isEmpty)
    }

    @Test func rejectsBadValues() {
        #expect(throws: GameProfileError.unsupportedFormat(2)) {
            try GameProfileParser.parse(Data(#"{"formatVersion":2,"steamAppId":1,"name":"x","status":"works"}"#.utf8))
        }
        #expect(throws: GameProfileError.missingField("steamAppId")) {
            try GameProfileParser.parse(Data(#"{"formatVersion":1,"name":"x","status":"works"}"#.utf8))
        }
        #expect(throws: GameProfileError.invalidValue(field: "status", value: "fine")) {
            try GameProfileParser.parse(Data(#"{"formatVersion":1,"steamAppId":1,"name":"x","status":"fine"}"#.utf8))
        }
        // D3DMetal needs process-wide settings, so a single game cannot switch to it.
        #expect(throws: GameProfileError.invalidValue(field: "graphics", value: "d3dmetal")) {
            try GameProfileParser.parse(profileJSON(#","graphics":"d3dmetal""#))
        }
        #expect(throws: GameProfileError.invalidValue(field: "executable", value: "bin/Game.exe")) {
            try GameProfileParser.parse(profileJSON(#","executable":"bin/Game.exe""#))
        }
        #expect(throws: GameProfileError.invalidValue(field: "dllOverrides", value: "d3d11=always")) {
            try GameProfileParser.parse(profileJSON(#","dllOverrides":{"d3d11":"always"}"#))
        }
    }
}

@Suite struct GameProfileCatalogTests {
    @Test func earlierDirectoriesWinAndBadFilesAreReported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("profiles-\(UUID().uuidString)")
        let mine = root.appendingPathComponent("mine"), bundled = root.appendingPathComponent("bundled")
        for dir in [mine, bundled] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        try profileJSON(#","graphics":"dxmt""#).write(to: mine.appendingPathComponent("4502710.json"))
        try profileJSON(#","graphics":"dxvk""#).write(to: bundled.appendingPathComponent("4502710.json"))
        try Data("{".utf8).write(to: bundled.appendingPathComponent("broken.json"))

        let catalog = GameProfileCatalog.load(directories: [mine, bundled])

        #expect(catalog.profile(for: 4502710)?.graphics == .dxmt)
        #expect(catalog.problems.map(\.file) == ["broken.json"])
    }
}

/// A bottle whose Steam library holds one installed game.
struct PlayFixture {
    let graphics = try! GraphicsFixture(components: RuntimeComponents(
        dxvkDirectory: URL(fileURLWithPath: "/rt/dxvk"), dxmtDirectory: URL(fileURLWithPath: "/rt/dxmt")))
    var service: BottleService { graphics.service }
    var runtime: FakeWineRuntime { graphics.base.runtime }
    let game: SteamGame

    init() throws {
        _ = try graphics.service.create(name: "steam", version: .win10)
        let prefix = graphics.base.store.prefixURL(for: "steam")
        game = SteamGame(appID: 4502710, name: "Stonewards",
                         installDirectory: SteamLibrary.steamDirectory(prefix: prefix)
                            .appendingPathComponent("steamapps/common/Stonewards"))
        runtime.calls.removeAll()
    }

    var steamExe: String {
        SteamLibrary.steamDirectory(prefix: graphics.base.store.prefixURL(for: "steam"))
            .appendingPathComponent("steam.exe").path
    }
}

@Suite struct PlayGameTests {
    let profile = GameProfile(steamAppID: 4502710, name: "Stonewards", status: .works, executable: "Stonewards.exe",
                              graphics: .dxmt, dllOverrides: ["xinput1_3": "native,builtin"],
                              launchArguments: ["-dx11"])

    @Test func appliesTheProfileThenLaunchesThroughSteam() throws {
        let f = try PlayFixture()
        _ = try f.service.play(f.game, profile: profile, bottle: "steam", arguments: ["-windowed"])

        let key = #"HKCU\Software\Wine\AppDefaults\Stonewards.exe\DllOverrides"#
        let writes = f.runtime.registryWrites()
        #expect(writes["\(key)\\d3d11"] == "native,builtin")
        #expect(writes["\(key)\\xinput1_3"] == "native,builtin")
        #expect(f.graphics.installer.installed.map(\.0) == [.dxmt])
        #expect(f.runtime.calls.last == .start("steam", f.steamExe, ["-applaunch", "4502710", "-dx11", "-windowed"]))
        // The profile is not recorded as the player's own choice.
        #expect(try f.graphics.base.store.load("steam").appGraphics.isEmpty)
    }

    @Test func thePlayersChoiceWinsOverTheProfile() throws {
        let f = try PlayFixture()
        try f.service.setAppGraphics("steam", executable: "Stonewards.exe", backend: .dxvk)
        f.graphics.installer.installed.removeAll()

        _ = try f.service.play(f.game, profile: profile, bottle: "steam", arguments: [])

        #expect(!f.graphics.installer.installed.map(\.0).contains(.dxmt))
        #expect(try f.service.gameGraphics(bottle: "steam", executable: "Stonewards.exe", profile: profile)
                == GameGraphics(backend: .dxvk, source: .player))
    }

    @Test func anUnchangedProfileIsAppliedOnce() throws {
        let f = try PlayFixture()
        _ = try f.service.play(f.game, profile: profile, bottle: "steam", arguments: [])
        f.runtime.calls.removeAll()

        _ = try f.service.play(f.game, profile: profile, bottle: "steam", arguments: [])

        #expect(f.runtime.calls == [.start("steam", f.steamExe, ["-applaunch", "4502710", "-dx11"])])
    }

    @Test func gamesWithoutAProfileJustLaunch() throws {
        let f = try PlayFixture()
        _ = try f.service.play(f.game, profile: nil, bottle: "steam", arguments: [])
        #expect(f.runtime.calls == [.start("steam", f.steamExe, ["-applaunch", "4502710"])])
    }

    @Test func reportsWhereAGamesGraphicsComeFrom() throws {
        let f = try PlayFixture()
        #expect(try f.service.gameGraphics(bottle: "steam", executable: "Stonewards.exe", profile: profile)
                == GameGraphics(backend: .dxmt, source: .profile))
        #expect(try f.service.gameGraphics(bottle: "steam", executable: "Stonewards.exe", profile: nil)
                == GameGraphics(backend: .wined3d, source: .bottle))
    }

    @Test func resettingAGameToAutomaticHandsItBackToItsProfile() throws {
        let f = try PlayFixture()
        try f.service.setAppGraphics("steam", executable: "Stonewards.exe", backend: .dxvk)
        _ = try f.service.play(f.game, profile: profile, bottle: "steam", arguments: [])
        f.runtime.calls.removeAll()
        f.graphics.installer.installed.removeAll()

        try f.service.clearAppGraphics("steam", executable: "Stonewards.exe")

        let key = #"HKCU\Software\Wine\AppDefaults\Stonewards.exe\DllOverrides"#
        #expect(f.runtime.calls == LaunchEnvironment.direct3DLibraries.map { .deleteRegistry("steam", key, $0) })
        #expect(try f.graphics.base.store.load("steam").appGraphics.isEmpty)
        #expect(try f.service.gameGraphics(bottle: "steam", executable: "Stonewards.exe", profile: profile)
                == GameGraphics(backend: .dxmt, source: .profile))

        _ = try f.service.play(f.game, profile: profile, bottle: "steam", arguments: [])
        #expect(f.graphics.installer.installed.map(\.0) == [.dxmt])
    }
}
