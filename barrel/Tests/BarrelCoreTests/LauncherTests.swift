import Foundation
import Testing
@testable import BarrelCore

struct LauncherFixture {
    let root: URL
    let installer: LauncherInstaller

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("barrel-launchers-\(UUID().uuidString)")
        installer = LauncherInstaller(directory: root.appendingPathComponent("Applications"))
    }

    func spec(name: String = "Stonewards", arguments: [String] = ["-applaunch", "4502710"],
              barrel: URL = URL(fileURLWithPath: "/opt/barrel/bin/barrel")) -> LauncherSpec {
        LauncherSpec(name: name, bottle: "steam", program: "/Bottles/steam/drive_c/Steam/steam.exe",
                     arguments: arguments, environment: ["BARREL_HOME": "/data/barrel"], barrelExecutable: barrel)
    }

    /// Writes a stand-in `barrel` that records its arguments and environment, one per line.
    func recordingBarrel() throws -> (executable: URL, output: URL) {
        let executable = root.appendingPathComponent("fake-barrel")
        let output = root.appendingPathComponent("calls.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
            #!/bin/sh
            for arg in "$@"; do printf '%s\\n' "$arg"; done > '\(output.path)'
            printf 'HOME_VAR=%s\\n' "$BARREL_HOME" >> '\(output.path)'
            """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (executable, output)
    }
}

@Suite struct LauncherTests {
    @Test func createsAnAppBundleNamedAfterTheLauncher() throws {
        let f = try LauncherFixture()
        let app = try f.installer.install(f.spec())

        #expect(app.lastPathComponent == "Stonewards.app")
        let plist = try #require(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")))
        #expect(plist["CFBundleName"] as? String == "Stonewards")
        #expect(plist["CFBundleExecutable"] as? String == "launcher")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["CFBundleIdentifier"] as? String == "org.barrel.launcher.Stonewards")
        #expect(plist["CFBundleIconFile"] == nil)

        let script = app.appendingPathComponent("Contents/MacOS/launcher")
        let permissions = try FileManager.default.attributesOfItem(atPath: script.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
    }

    @Test func launcherRunsTheProgramThroughBarrelWithItsEnvironment() throws {
        let f = try LauncherFixture()
        let fake = try f.recordingBarrel()
        let app = try f.installer.install(f.spec(arguments: ["-applaunch", "4502710", "it's \"quoted\" $HOME"],
                                                 barrel: fake.executable))

        let process = Process()
        process.executableURL = app.appendingPathComponent("Contents/MacOS/launcher")
        process.environment = ["PATH": "/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let lines = try String(contentsOf: fake.output, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines == ["run", "--bottle", "steam", "/Bottles/steam/drive_c/Steam/steam.exe",
                          "-applaunch", "4502710", "it's \"quoted\" $HOME", "HOME_VAR=/data/barrel"])
    }

    @Test func iconIsStoredInTheBundle() throws {
        let f = try LauncherFixture()
        let app = try f.installer.install(f.spec(), icon: Data("icns".utf8))
        let plist = try #require(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")))
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
        #expect(try Data(contentsOf: app.appendingPathComponent("Contents/Resources/AppIcon.icns")) == Data("icns".utf8))
    }

    @Test func installingAgainReplacesTheLauncher() throws {
        let f = try LauncherFixture()
        _ = try f.installer.install(f.spec(), icon: Data("old".utf8))
        let app = try f.installer.install(f.spec())
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/AppIcon.icns").path))
        #expect(try f.installer.list() == ["Stonewards"])
    }

    @Test func listsAndRemovesLaunchers() throws {
        let f = try LauncherFixture()
        #expect(try f.installer.list().isEmpty)
        _ = try f.installer.install(f.spec(name: "B Game"))
        _ = try f.installer.install(f.spec(name: "A Game"))
        #expect(try f.installer.list() == ["A Game", "B Game"])

        try f.installer.remove("A Game")
        #expect(try f.installer.list() == ["B Game"])
        #expect(throws: LauncherError.notFound("A Game")) { try f.installer.remove("A Game") }
    }

    @Test(arguments: ["", ".hidden", "a/b", "a:b"])
    func rejectsInvalidNames(name: String) throws {
        let f = try LauncherFixture()
        #expect(throws: LauncherError.invalidName(name)) { try f.installer.install(f.spec(name: name)) }
    }

    @Test func bundleIdentifierKeepsOnlySafeCharacters() throws {
        let f = try LauncherFixture()
        let app = try f.installer.install(f.spec(name: "Baldur's Gate 3"))
        let plist = try #require(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")))
        #expect(plist["CFBundleIdentifier"] as? String == "org.barrel.launcher.Baldur-s-Gate-3")
    }
}
