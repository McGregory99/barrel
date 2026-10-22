import Foundation
import Testing
@testable import BarrelCore

@Suite struct KeyValuesTests {
    @Test func parsesNestedBlocksEscapesAndComments() throws {
        let text = #"""
        "libraryfolders"
        {
            // a comment
            "0"
            {
                "path"		"C:\\Program Files (x86)\\Steam"
                "label"		"say \"hi\""
                "apps"
                {
                    "4502710"		"2024243882"
                }
            }
        }
        """#
        let root = try KeyValues.parse(text)
        let library = try #require(root["libraryfolders"]?["0"])
        #expect(library["path"]?.string == #"C:\Program Files (x86)\Steam"#)
        #expect(library["label"]?.string == #"say "hi""#)
        #expect(library["apps"]?["4502710"]?.string == "2024243882")
    }

    @Test func rejectsUnbalancedBraces() {
        #expect(throws: KeyValuesError.self) { try KeyValues.parse(#""a" { "b" "c""#) }
    }
}

/// A Wine prefix with Steam's library files, built in a temporary directory.
struct FakeSteamPrefix {
    let prefix = FileManager.default.temporaryDirectory.appendingPathComponent("steam-prefix-\(UUID().uuidString)")
    var steamapps: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps") }

    /// Maps `letter:` to `target` the way Wine does (a symlink in dosdevices).
    func mapDrive(_ letter: String, to target: String) throws {
        let dosdevices = prefix.appendingPathComponent("dosdevices")
        try FileManager.default.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dosdevices.appendingPathComponent("\(letter):").path,
                                                   withDestinationPath: target)
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func manifest(appID: Int, name: String, installdir: String, stateFlags: Int = 4) -> String {
        """
        "AppState"
        {
        	"appid"		"\(appID)"
        	"name"		"\(name)"
        	"StateFlags"		"\(stateFlags)"
        	"installdir"		"\(installdir)"
        }
        """
    }
}

@Suite struct SteamLibraryTests {
    @Test func listsFullyInstalledGamesAcrossLibraries() throws {
        let fake = FakeSteamPrefix()
        let games = fake.prefix.appendingPathComponent("games-drive")
        try fake.mapDrive("c", to: "../drive_c")
        try fake.mapDrive("d", to: games.path)
        try fake.write(#"""
            "libraryfolders"
            {
            	"0" { "path" "C:\\Program Files (x86)\\Steam" }
            	"1" { "path" "D:\\SteamLibrary" }
            }
            """#, to: fake.steamapps.appendingPathComponent("libraryfolders.vdf"))
        try fake.write(fake.manifest(appID: 4502710, name: "Stonewards", installdir: "Stonewards"),
                       to: fake.steamapps.appendingPathComponent("appmanifest_4502710.acf"))
        // Still downloading (StateFlags without the "fully installed" bit) and Steam's own redistributables.
        try fake.write(fake.manifest(appID: 10, name: "Half-Done", installdir: "HD", stateFlags: 1026),
                       to: fake.steamapps.appendingPathComponent("appmanifest_10.acf"))
        try fake.write(fake.manifest(appID: 228980, name: "Steamworks Common Redistributables",
                                     installdir: "Steamworks Shared"),
                       to: fake.steamapps.appendingPathComponent("appmanifest_228980.acf"))
        let otherLibrary = games.appendingPathComponent("SteamLibrary/steamapps")
        try fake.write(fake.manifest(appID: 220, name: "Aardvark Quest", installdir: "Aardvark"),
                       to: otherLibrary.appendingPathComponent("appmanifest_220.acf"))

        let installed = SteamLibrary.installedGames(prefix: fake.prefix)

        #expect(installed.map(\.appID) == [220, 4502710])  // sorted by name
        #expect(installed.map(\.name) == ["Aardvark Quest", "Stonewards"])
        #expect(installed[0].installDirectory.path
                == otherLibrary.appendingPathComponent("common/Aardvark").resolvingSymlinksInPath().path)
        #expect(installed[1].installDirectory.path.hasSuffix("Steam/steamapps/common/Stonewards"))
    }

    @Test func noSteamMeansNoGames() {
        #expect(SteamLibrary.installedGames(prefix: FakeSteamPrefix().prefix).isEmpty)
    }

    @Test func fallsBackToTheDefaultLibraryWithoutLibraryFolders() throws {
        let fake = FakeSteamPrefix()
        try fake.write(fake.manifest(appID: 4502710, name: "Stonewards", installdir: "Stonewards"),
                       to: fake.steamapps.appendingPathComponent("appmanifest_4502710.acf"))
        #expect(SteamLibrary.installedGames(prefix: fake.prefix).map(\.appID) == [4502710])
    }

    @Test func picksTheGameExecutableAndSkipsHelpers() throws {
        let fake = FakeSteamPrefix()
        let dir = fake.prefix.appendingPathComponent("game")
        for exe in ["UnityCrashHandler64.exe", "Stonewards.exe", "unins000.exe", "Redist/vc_redist.x64.exe"] {
            try fake.write("MZ", to: dir.appendingPathComponent(exe))
        }
        let game = SteamGame(appID: 4502710, name: "Stonewards", installDirectory: dir)
        #expect(SteamLibrary.mainExecutable(of: game)?.lastPathComponent == "Stonewards.exe")
    }
}
