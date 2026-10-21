import BarrelCore
import Foundation
import Testing
@testable import BarrelRecipes

final class FakeDownloader: Downloader {
    var requests: [URL] = []
    var content = Data("payload".utf8)
    func download(from url: URL, to destination: URL) throws {
        requests.append(url)
        try content.write(to: destination)
    }
}

final class FakeHost: RecipeHost {
    enum Event: Equatable {
        case create(String, WindowsVersion)
        case graphics(GraphicsBackend)
        case msync(Bool)
        case appGraphics(String, GraphicsBackend)
        case run(String, [String])
    }
    var events: [Event] = []
    var existing: Set<String> = []
    var exitStatus: Int32 = 0
    let root = URL(fileURLWithPath: "/prefixes")
    func bottleExists(_ name: String) -> Bool { existing.contains(name) }
    func createBottle(name: String, version: WindowsVersion, description: String?) throws {
        events.append(.create(name, version)); existing.insert(name)
    }
    func setGraphics(_ name: String, backend: GraphicsBackend) throws { events.append(.graphics(backend)) }
    func setMSync(_ name: String, enabled: Bool) throws { events.append(.msync(enabled)) }
    func setAppGraphics(_ name: String, executable: String, backend: GraphicsBackend) throws {
        events.append(.appGraphics(executable, backend))
    }
    func prefixURL(for name: String) -> URL { root.appendingPathComponent(name) }
    func run(_ path: String, arguments: [String], bottle: String) throws -> Int32 {
        events.append(.run(path, arguments)); return exitStatus
    }
}

struct Harness {
    let downloader = FakeDownloader()
    let host = FakeHost()
    let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
    var cache: DownloadCache { DownloadCache(directory: cacheDir, downloader: downloader) }
    var executor: RecipeExecutor { RecipeExecutor(host: host, downloads: cache) }
    var payloadHash: String { SHA256Hasher.hex(of: Data("payload".utf8)) }
    func download(_ hash: String? = nil) -> DownloadStep {
        DownloadStep(url: URL(string: "https://e.com/a.exe")!, sha256: hash ?? payloadHash, fileName: "a.exe")
    }
}

@Suite struct DownloadCacheTests {
    @Test func downloadsOnceThenServesFromCache() throws {
        let h = Harness()
        let first = try h.cache.fetch(h.download())
        _ = try h.cache.fetch(h.download())
        #expect(h.downloader.requests.count == 1)
        #expect(try Data(contentsOf: first) == Data("payload".utf8))
    }

    @Test func redownloadsWhenCachedFileIsCorrupt() throws {
        let h = Harness()
        let url = try h.cache.fetch(h.download())
        try Data("corrupt".utf8).write(to: url)
        _ = try h.cache.fetch(h.download())
        #expect(h.downloader.requests.count == 2)
        #expect(try Data(contentsOf: url) == Data("payload".utf8))
    }

    @Test func hashMismatchFailsAndLeavesNoFile() throws {
        let h = Harness()
        let wrong = String(repeating: "0", count: 64)
        #expect(throws: RecipeError.hashMismatch(file: "a.exe", expected: wrong, actual: h.payloadHash)) {
            try h.cache.fetch(h.download(wrong))
        }
        #expect(!FileManager.default.fileExists(atPath: h.cache.localURL(for: "a.exe").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.cacheDir.path).isEmpty)
    }
}

@Suite struct ExecutorTests {
    func recipe(_ id: String, deps: [String] = [], bottle: BottleSettings = BottleSettings(), steps: [Step]) -> Recipe {
        Recipe(id: id, name: id, description: nil, bottle: bottle, dependencies: deps, steps: steps)
    }

    @Test func appliesBottleSettingsThenStepsInOrderWithDependenciesFirst() throws {
        let h = Harness()
        let base = recipe("base", steps: [.download(h.download()), .run(RunStep(file: "a.exe", path: nil, arguments: ["/q"], expectedExitCodes: [0]))])
        let app = recipe("app", deps: ["base"],
                         bottle: BottleSettings(windowsVersion: .win7, graphicsBackend: .dxvk, msync: false),
                         steps: [.run(RunStep(file: nil, path: "/bin/tool", arguments: [], expectedExitCodes: [0]))])
        let name = try h.executor.install("app", catalog: RecipeCatalog(recipes: [base, app]))
        #expect(name == "app")
        #expect(h.host.events == [
            .create("app", .win7), .graphics(.dxvk), .msync(false),
            .run(h.cache.localURL(for: "a.exe").path, ["/q"]),
            .run("/bin/tool", []),
        ])
    }

    @Test func appliesPerAppGraphicsAfterBottleBackendInNameOrder() throws {
        let h = Harness()
        let app = recipe("app", bottle: BottleSettings(graphicsBackend: .dxvk,
                                                        appGraphics: ["zz.exe": .wined3d, "aa.exe": .dxvk]),
                         steps: [])
        _ = try h.executor.install("app", catalog: RecipeCatalog(recipes: [app]))
        #expect(h.host.events == [
            .create("app", .win10), .graphics(.dxvk), .appGraphics("aa.exe", .dxvk), .appGraphics("zz.exe", .wined3d),
        ])
    }

    @Test func usesExistingBottleWithoutCreatingIt() throws {
        let h = Harness()
        h.host.existing = ["mine"]
        try h.executor.install("app", catalog: RecipeCatalog(recipes: [recipe("app", steps: [])]), bottle: "mine")
        #expect(h.host.events.isEmpty)
    }

    @Test func dllOverrideWritesWineDllOverridesViaRegExe() throws {
        let h = Harness()
        h.host.existing = ["b"]
        let step = Step.dllOverride(DLLOverrideStep(dll: "d3dcompiler_47", mode: .nativeBuiltin))
        try h.executor.install("app", catalog: RecipeCatalog(recipes: [recipe("app", steps: [step])]), bottle: "b")
        #expect(h.host.events == [.run(
            "/prefixes/b/drive_c/windows/system32/reg.exe",
            ["add", "HKCU\\Software\\Wine\\DllOverrides", "/v", "d3dcompiler_47", "/t", "REG_SZ", "/d", "native,builtin", "/f"])])
    }

    @Test func disabledOverrideWritesEmptyValueAndRegistryStepUsesItsType() throws {
        let h = Harness()
        h.host.existing = ["b"]
        let steps: [Step] = [
            .dllOverride(DLLOverrideStep(dll: "mscoree", mode: .disabled)),
            .registry(RegistryStep(key: "HKCU\\Software\\X", name: "N", type: .dword, data: "1")),
        ]
        try h.executor.install("app", catalog: RecipeCatalog(recipes: [recipe("app", steps: steps)]), bottle: "b")
        guard case .run(_, let first) = h.host.events[0], case .run(_, let second) = h.host.events[1] else {
            Issue.record("expected two reg.exe runs"); return
        }
        #expect(first.suffix(3) == ["/d", "", "/f"])
        #expect(second == ["add", "HKCU\\Software\\X", "/v", "N", "/t", "REG_DWORD", "/d", "1", "/f"])
    }

    @Test func windowsPathsMapIntoTheBottleDriveC() throws {
        let h = Harness()
        h.host.existing = ["b"]
        let step = Step.run(RunStep(file: nil, path: "C:\\Setup\\x.exe", arguments: [], expectedExitCodes: [0]))
        try h.executor.install("app", catalog: RecipeCatalog(recipes: [recipe("app", steps: [step])]), bottle: "b")
        #expect(h.host.events == [.run("/prefixes/b/drive_c/Setup/x.exe", [])])
    }

    @Test func unexpectedExitCodeStopsTheInstall() throws {
        let h = Harness()
        h.host.existing = ["b"]
        h.host.exitStatus = 5
        let steps: [Step] = [
            .run(RunStep(file: nil, path: "/a", arguments: [], expectedExitCodes: [0])),
            .run(RunStep(file: nil, path: "/b", arguments: [], expectedExitCodes: [0])),
        ]
        #expect(throws: RecipeError.self) {
            try h.executor.install("app", catalog: RecipeCatalog(recipes: [recipe("app", steps: steps)]), bottle: "b")
        }
        #expect(h.host.events.count == 1)
    }

    @Test func acceptsListedNonZeroExitCode() throws {
        let h = Harness()
        h.host.existing = ["b"]
        h.host.exitStatus = 3010
        let step = Step.run(RunStep(file: nil, path: "/a", arguments: [], expectedExitCodes: [0, 3010]))
        try h.executor.install("app", catalog: RecipeCatalog(recipes: [recipe("app", steps: [step])]), bottle: "b")
        #expect(h.host.events.count == 1)
    }
}
