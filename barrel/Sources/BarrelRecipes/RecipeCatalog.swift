import Foundation

/// Recipes discovered in one or more directories (`*.json`). Earlier directories win on duplicate ids.
public struct RecipeCatalog {
    public struct Problem: Equatable {
        public let file: String
        public let message: String
    }

    public private(set) var recipes: [String: Recipe] = [:]
    public private(set) var problems: [Problem] = []

    public init(recipes: [Recipe] = []) {
        for recipe in recipes where self.recipes[recipe.id] == nil { self.recipes[recipe.id] = recipe }
    }

    public static func load(directories: [URL]) -> RecipeCatalog {
        var catalog = RecipeCatalog()
        let fileManager = FileManager.default
        for directory in directories {
            let files = ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { $0.hasSuffix(".json") }.sorted()
            for file in files {
                do {
                    let recipe = try RecipeParser.parse(Data(contentsOf: directory.appendingPathComponent(file)))
                    if catalog.recipes[recipe.id] == nil { catalog.recipes[recipe.id] = recipe }
                } catch {
                    catalog.problems.append(Problem(file: file, message: "\(error)"))
                }
            }
        }
        return catalog
    }

    public var sorted: [Recipe] { recipes.values.sorted { $0.id < $1.id } }

    public func recipe(_ id: String) throws -> Recipe {
        guard let recipe = recipes[id] else { throw RecipeError.unknownRecipe(id) }
        return recipe
    }

    /// `id` and its transitive dependencies, dependencies first, each once.
    public func installOrder(for id: String) throws -> [Recipe] {
        var ordered: [Recipe] = []
        var done: Set<String> = []
        var stack: [String] = []

        func visit(_ id: String, requiredBy parent: String?) throws {
            guard let recipe = recipes[id] else {
                if let parent { throw RecipeError.unknownDependency(recipe: parent, dependency: id) }
                throw RecipeError.unknownRecipe(id)
            }
            if let start = stack.firstIndex(of: id) {
                throw RecipeError.dependencyCycle(Array(stack[start...]) + [id])
            }
            if done.contains(id) { return }
            stack.append(id)
            for dependency in recipe.dependencies { try visit(dependency, requiredBy: id) }
            stack.removeLast()
            done.insert(id)
            ordered.append(recipe)
        }
        try visit(id, requiredBy: nil)
        return ordered
    }
}
