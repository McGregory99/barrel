import BarrelAppKit
import BarrelCore
import SwiftUI

struct CreateBottleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var version = WindowsVersion.win10
    @State private var description = ""
    let onCreate: (String, WindowsVersion, String?) -> Void

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Windows version", selection: $version) {
                ForEach(WindowsVersion.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            TextField("Description", text: $description)
            Text("Creating a bottle can take up to a minute.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    onCreate(name.trimmingCharacters(in: .whitespaces), version, description.isEmpty ? nil : description)
                    dismiss()
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}

/// Single-text-field sheet used for copy and restore.
struct NameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let prompt: String
    let action: String
    var allowsEmpty = false
    let onSubmit: (String) -> Void
    @State private var text: String

    init(title: String, prompt: String, action: String, initial: String, allowsEmpty: Bool = false,
         onSubmit: @escaping (String) -> Void) {
        self.title = title; self.prompt = prompt; self.action = action
        self.allowsEmpty = allowsEmpty; self.onSubmit = onSubmit
        _text = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField(prompt, text: $text).frame(width: 320)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(action) {
                    onSubmit(text.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!allowsEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }
}

/// Picks an install recipe and the bottle to install it into (a new one named after the recipe by default).
struct InstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recipes: [RecipeSummary]
    let bottles: [String]
    let onInstall: (String, String?) -> Void
    @State private var recipe: String?
    @State private var target: String

    private static let newBottle = "\u{0}new"

    init(recipes: [RecipeSummary], bottles: [String],
         onInstall: @escaping (String, String?) -> Void) {
        self.recipes = recipes
        self.bottles = bottles
        self.onInstall = onInstall
        _target = State(initialValue: Self.newBottle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install Software").font(.headline)
            if recipes.isEmpty {
                ContentUnavailableView("No recipes", systemImage: "shippingbox",
                                       description: Text("Add a recipe folder in Settings, or put recipes in the data directory's Recipes folder."))
                    .frame(height: 220)
            } else {
                List(recipes, selection: $recipe) { recipe in
                    VStack(alignment: .leading) {
                        Text(recipe.name)
                        if let description = recipe.description {
                            Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(description)
                        }
                    }
                    .tag(recipe.id)
                }
                .frame(height: 220)
            }
            Picker("Install into", selection: $target) {
                Text("New bottle named after the software").tag(Self.newBottle)
                ForEach(bottles, id: \.self) { Text($0).tag($0) }
            }
            Text("Downloads are checked against their SHA-256 before running.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Install") {
                    if let recipe { onInstall(recipe, target == Self.newBottle ? nil : target) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(recipe == nil)
            }
        }
        .padding()
        .frame(width: 460)
    }
}

struct BusyBanner: View {
    let message: String
    var body: some View {
        HStack {
            ProgressView().controlSize(.small)
            Text(message)
        }
        .padding(10)
        .background(.regularMaterial, in: Capsule())
        .padding()
    }
}
