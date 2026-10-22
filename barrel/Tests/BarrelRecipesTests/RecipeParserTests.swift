import BarrelCore
import Foundation
import Testing
@testable import BarrelRecipes

let validSHA = String(repeating: "ab", count: 32)

func recipeJSON(id: String = "app", dependencies: String = "[]", steps: String = "[]", bottle: String = "{}") -> Data {
    Data("""
    {"formatVersion":1,"id":"\(id)","name":"App \(id)","description":"d","bottle":\(bottle),
     "dependencies":\(dependencies),"steps":\(steps)}
    """.utf8)
}

@Suite struct RecipeParserTests {
    @Test func parsesAllStepKindsAndBottleSettings() throws {
        let steps = """
        [{"kind":"download","url":"https://example.com/a.exe","sha256":"\(validSHA.uppercased())","fileName":"a.exe"},
         {"kind":"run","file":"a.exe","arguments":["/quiet"],"expectedExitCodes":[0,3010]},
         {"kind":"registry","key":"HKCU\\\\Software\\\\X","name":"V","type":"REG_DWORD","data":7},
         {"kind":"dllOverride","dll":"d3dcompiler_47","mode":"native,builtin"}]
        """
        let recipe = try RecipeParser.parse(recipeJSON(
            steps: steps, bottle: #"{"windowsVersion":"win7_64","graphicsBackend":"dxvk","msync":false}"#))
        #expect(recipe.id == "app")
        #expect(recipe.description == "d")
        #expect(recipe.bottle == BottleSettings(windowsVersion: .win7, graphicsBackend: .dxvk, msync: false))
        #expect(recipe.steps.count == 4)
        #expect(recipe.steps[0] == .download(DownloadStep(
            url: URL(string: "https://example.com/a.exe")!, sha256: validSHA, fileName: "a.exe")))
        #expect(recipe.steps[1] == .run(RunStep(file: "a.exe", path: nil, arguments: ["/quiet"], expectedExitCodes: [0, 3010])))
        #expect(recipe.steps[2] == .registry(RegistryStep(key: "HKCU\\Software\\X", name: "V", type: .dword, data: "7")))
        #expect(recipe.steps[3] == .dllOverride(DLLOverrideStep(dll: "d3dcompiler_47", mode: .nativeBuiltin)))
    }

    @Test func hiddenRecipesStayInstallableButOutOfTheList() throws {
        let hidden = try RecipeParser.parse(Data("""
            {"formatVersion":1,"id":"vcredist-x64","name":"VC++","hidden":true,"steps":[]}
            """.utf8))
        let shown = try RecipeParser.parse(recipeJSON(id: "steam"))
        #expect(hidden.hidden && !shown.hidden)
        let catalog = RecipeCatalog(recipes: [hidden, shown])
        #expect(catalog.visible.map(\.id) == ["steam"])
        #expect(catalog.sorted.map(\.id) == ["steam", "vcredist-x64"])
        #expect(throws: RecipeError.self) {
            try RecipeParser.parse(Data(#"{"formatVersion":1,"id":"x","name":"X","hidden":"yes","steps":[]}"#.utf8))
        }
    }

    @Test func acceptsMaintainerNotesAlongsideTheDescription() throws {
        let data = Data("""
            {"formatVersion":1,"id":"app","name":"App","description":"Short.","notes":"Why the fixes exist.",
             "steps":[]}
            """.utf8)
        #expect(try RecipeParser.parse(data).description == "Short.")
    }

    @Test func parsesPerAppGraphics() throws {
        let recipe = try RecipeParser.parse(recipeJSON(bottle: #"{"graphicsBackend":"dxvk","appGraphics":{"steamwebhelper.exe":"wined3d"}}"#))
        #expect(recipe.bottle.graphicsBackend == .dxvk)
        #expect(recipe.bottle.appGraphics == ["steamwebhelper.exe": .wined3d])
    }

    @Test func rejectsUnknownPerAppBackend() {
        #expect(throws: RecipeError.self) {
            try RecipeParser.parse(recipeJSON(bottle: #"{"appGraphics":{"game.exe":"vulkan"}}"#))
        }
    }

    @Test func rejectsNonStringPerAppBackend() {
        #expect(throws: RecipeError.self) {
            try RecipeParser.parse(recipeJSON(bottle: #"{"appGraphics":{"game.exe":1}}"#))
        }
    }

    @Test func rejectsUnknownStepKind() {
        #expect(throws: RecipeError.unknownStepKind(kind: "teleport", step: 1)) {
            try RecipeParser.parse(recipeJSON(steps: #"[{"kind":"teleport"}]"#))
        }
    }

    @Test func rejectsDownloadWithoutSHA256() {
        let step = #"[{"kind":"download","url":"https://e.com/a.exe","fileName":"a.exe"}]"#
        #expect(throws: RecipeError.missingSHA256(step: 1)) { try RecipeParser.parse(recipeJSON(steps: step)) }
    }

    @Test func rejectsMalformedSHA256() {
        let step = #"[{"kind":"download","url":"https://e.com/a.exe","sha256":"TODO","fileName":"a.exe"}]"#
        #expect(throws: RecipeError.invalidSHA256(step: 1, value: "TODO")) { try RecipeParser.parse(recipeJSON(steps: step)) }
    }

    @Test func rejectsRunOfUndeclaredDownload() {
        #expect(throws: RecipeError.unknownDownloadReference(file: "x.exe", step: 1)) {
            try RecipeParser.parse(recipeJSON(steps: #"[{"kind":"run","file":"x.exe"}]"#))
        }
    }

    @Test func rejectsMissingFieldsAndBadVersion() {
        #expect(throws: RecipeError.missingField("id")) {
            try RecipeParser.parse(Data(#"{"formatVersion":1,"name":"x"}"#.utf8))
        }
        #expect(throws: RecipeError.unsupportedFormatVersion(2)) {
            try RecipeParser.parse(Data(#"{"formatVersion":2,"id":"a","name":"x"}"#.utf8))
        }
        #expect(throws: RecipeError.missingField("formatVersion")) {
            try RecipeParser.parse(Data(#"{"id":"a","name":"x"}"#.utf8))
        }
    }

    @Test func rejectsNonJSON() {
        #expect(throws: (any Error).self) { try RecipeParser.parse(Data("nope".utf8)) }
    }

    @Test func rejectsBadOverrideModeAndRegistryKey() {
        #expect(throws: (any Error).self) {
            try RecipeParser.parse(recipeJSON(steps: #"[{"kind":"dllOverride","dll":"x","mode":"maybe"}]"#))
        }
        #expect(throws: (any Error).self) {
            try RecipeParser.parse(recipeJSON(steps: #"[{"kind":"registry","key":"Software\\X","name":"a","data":"b"}]"#))
        }
    }
}

@Suite struct ResolverTests {
    func recipe(_ id: String, deps: [String] = []) -> Recipe {
        Recipe(id: id, name: id, description: nil, bottle: BottleSettings(), dependencies: deps, steps: [])
    }

    @Test func ordersDependenciesFirstAndOnlyOnce() throws {
        let catalog = RecipeCatalog(recipes: [
            recipe("app", deps: ["a", "b"]), recipe("a", deps: ["base"]), recipe("b", deps: ["base"]), recipe("base"),
        ])
        #expect(try catalog.installOrder(for: "app").map(\.id) == ["base", "a", "b", "app"])
    }

    @Test func detectsCycles() {
        let catalog = RecipeCatalog(recipes: [recipe("a", deps: ["b"]), recipe("b", deps: ["a"])])
        #expect(throws: RecipeError.dependencyCycle(["a", "b", "a"])) { try catalog.installOrder(for: "a") }
    }

    @Test func reportsUnknownDependencyAndRecipe() {
        let catalog = RecipeCatalog(recipes: [recipe("a", deps: ["ghost"])])
        #expect(throws: RecipeError.unknownDependency(recipe: "a", dependency: "ghost")) { try catalog.installOrder(for: "a") }
        #expect(throws: RecipeError.unknownRecipe("zzz")) { try catalog.installOrder(for: "zzz") }
    }

    @Test func loadsDirectoriesAndReportsBrokenFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recipes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try recipeJSON(id: "good").write(to: dir.appendingPathComponent("good.json"))
        try Data("{".utf8).write(to: dir.appendingPathComponent("bad.json"))
        let catalog = RecipeCatalog.load(directories: [dir, dir.appendingPathComponent("missing")])
        #expect(catalog.sorted.map(\.id) == ["good"])
        #expect(catalog.problems.map(\.file) == ["bad.json"])
    }
}
