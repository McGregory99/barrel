import Foundation
import Testing
@testable import BarrelCore

/// Runs `ProcessWineRuntime` against stand-in `wine`/`wineserver` scripts that log each call's
/// first argument and WINEDLLOVERRIDES.
struct RecordingWine {
    let directory: URL
    let log: URL
    let runtime: ProcessWineRuntime
    let prefix: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("fake-wine-\(UUID().uuidString)")
        log = directory.appendingPathComponent("calls.log")
        prefix = directory.appendingPathComponent("prefix")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for tool in ["wine", "wineserver"] {
            let script = directory.appendingPathComponent(tool)
            try """
                #!/bin/sh
                printf '%s %s|%s\\n' '\(tool)' "$1" "${WINEDLLOVERRIDES-unset}" >> '\(log.path)'
                """.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }
        runtime = ProcessWineRuntime(wineBinary: directory.appendingPathComponent("wine"))
    }

    func calls() throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    }
}

@Suite struct ProcessWineRuntimeTests {
    @Test func maintenanceCommandsSkipTheMonoAndGeckoInstallers() throws {
        let wine = try RecordingWine()
        try wine.runtime.initializePrefix(at: wine.prefix, environment: [:])
        try wine.runtime.setWindowsVersion(.win10, prefix: wine.prefix, environment: [:])
        try wine.runtime.setRegistryValue(key: "HKCU\\Software\\Wine\\DllOverrides", name: "d3d11",
                                          data: "native,builtin", prefix: wine.prefix, environment: [:])
        #expect(try wine.calls() == [
            "wine wineboot|mscoree,mshtml=", "wineserver -w|mscoree,mshtml=",
            "wine winecfg|mscoree,mshtml=", "wineserver -w|mscoree,mshtml=",
            "wine reg|mscoree,mshtml=",
        ])
    }

    @Test func maintenanceKeepsOverridesFromTheBottleEnvironment() throws {
        let wine = try RecordingWine()
        try wine.runtime.setRegistryValue(key: "HKCU\\X", name: "y", data: "z", prefix: wine.prefix,
                                          environment: ["WINEDLLOVERRIDES": "dxgi=n"])
        #expect(try wine.calls() == ["wine reg|dxgi=n;mscoree,mshtml="])
    }

    @Test func runningProgramsLeavesMonoAndGeckoAvailable() throws {
        let wine = try RecordingWine()
        _ = try wine.runtime.start("/tmp/setup.exe", arguments: [], prefix: wine.prefix, environment: [:])
        let call = try #require(try wine.calls().first)
        #expect(call.hasPrefix("wine start|"))
        #expect(!call.contains("mscoree"))
    }
}
