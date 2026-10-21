import BarrelCore
import Foundation
import Testing
@testable import BarrelAppKit

struct BarrelCoreGatewayTests {
    @Test func recipesComeFromTheConfiguredFoldersSortedById() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gateway-\(UUID().uuidString)")
        let recipes = root.appendingPathComponent("recipes")
        try FileManager.default.createDirectory(at: recipes, withIntermediateDirectories: true)
        for (id, name) in [("zeta", "Zeta App"), ("alpha", "Alpha App")] {
            let json = #"{"formatVersion":1,"id":"\#(id)","name":"\#(name)","description":"d","steps":[]}"#
            try Data(json.utf8).write(to: recipes.appendingPathComponent("\(id).json"))
        }
        var settings = AppSettings(dataDirectory: root.appendingPathComponent("data"))
        settings.wineBinary = "/nonexistent/wine"
        settings.recipesDirectory = recipes.path

        let gateway = try BarrelCoreGateway(settings: settings)

        #expect(try gateway.recipes() == [RecipeSummary(id: "alpha", name: "Alpha App", description: "d"),
                                          RecipeSummary(id: "zeta", name: "Zeta App", description: "d")])
    }
}
