import BarrelCore
import BarrelRecipes
import Foundation
import Testing
@testable import BarrelAppKit

@MainActor
struct RecipeInstallTests {
    let steam = RecipeSummary(id: "steam", name: "Steam", description: "Valve's game store")

    @Test func loadRecipesListsTheCatalog() async {
        let gateway = FakeGateway()
        gateway.recipeList = [steam]
        let model = BottleListViewModel(gateway: gateway)
        await model.loadRecipes()
        #expect(model.recipes == [steam])
        #expect(model.errorMessage == nil)
    }

    @Test func installingIntoANewBottleSelectsIt() async {
        let gateway = FakeGateway()
        let model = BottleListViewModel(gateway: gateway)
        await model.install(recipe: "steam", into: nil)
        #expect(gateway.installs.map(\.recipe) == ["steam"])
        #expect(gateway.installs.map(\.bottle) == [nil])
        #expect(model.bottles.map(\.name) == ["steam"])
        #expect(model.selection == "steam")
        #expect(!model.isBusy)
    }

    @Test func installingIntoAnExistingBottleKeepsIt() async {
        let gateway = FakeGateway(bottles: [Bottle(name: "games", windowsVersion: .win10)])
        let model = BottleListViewModel(gateway: gateway)
        await model.install(recipe: "steam", into: "games")
        #expect(gateway.installs.map(\.bottle) == ["games"])
        #expect(model.bottles.map(\.name) == ["games"])
        #expect(model.selection == "games")
    }

    @Test func installFailureShowsTheRecipeError() async {
        let gateway = FakeGateway()
        gateway.failure = RecipeError.unknownRecipe("nope")
        let model = BottleListViewModel(gateway: gateway)
        await model.install(recipe: "nope", into: nil)
        #expect(model.errorMessage == RecipeError.unknownRecipe("nope").description)
        #expect(model.selection == nil)
    }
}
