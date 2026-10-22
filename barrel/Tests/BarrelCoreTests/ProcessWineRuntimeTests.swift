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

    init(stderr: String = "", status: Int32 = 0, diagnostics: FileHandle = .standardError) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("fake-wine-\(UUID().uuidString)")
        log = directory.appendingPathComponent("calls.log")
        prefix = directory.appendingPathComponent("prefix")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for tool in ["wine", "wineserver"] {
            let script = directory.appendingPathComponent(tool)
            try """
                #!/bin/sh
                printf '%s %s|%s\\n' '\(tool)' "$1" "${WINEDLLOVERRIDES-unset}" >> '\(log.path)'
                printf '%s' "\(stderr)" >&2
                exit \(status)
                """.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        }
        runtime = ProcessWineRuntime(wineBinary: directory.appendingPathComponent("wine"), diagnostics: diagnostics)
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

    @Test func maintenanceHidesWineChatterWhenItSucceeds() throws {
        let sink = try CapturedOutput()
        let wine = try RecordingWine(stderr: "msync: up and running.", diagnostics: sink.handle)
        try wine.runtime.setRegistryValue(key: "HKCU\\X", name: "y", data: "z", prefix: wine.prefix, environment: [:])
        #expect(try sink.text() == "")
    }

    @Test func maintenanceShowsWineOutputWhenItFails() throws {
        let sink = try CapturedOutput()
        let wine = try RecordingWine(stderr: "mvk=$MVK_CONFIG_LOG_LEVEL err:reg:failed", status: 1,
                                     diagnostics: sink.handle)
        #expect(throws: WineRuntimeError.commandFailed(command: "wine reg add HKCU\\X /v y /t REG_SZ /d z /f",
                                                      status: 1)) {
            try wine.runtime.setRegistryValue(key: "HKCU\\X", name: "y", data: "z", prefix: wine.prefix,
                                              environment: [:])
        }
        // MoltenVK's info log is off unless the caller asks for it.
        #expect(try sink.text() == "mvk=1 err:reg:failed")
    }
}

/// A file standing in for stderr.
struct CapturedOutput {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-\(UUID().uuidString)")
    let handle: FileHandle

    init() throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func text() throws -> String { try String(contentsOf: url, encoding: .utf8) }
}
