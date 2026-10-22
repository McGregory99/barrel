import BarrelAppKit
import BarrelCore
import SwiftUI

/// Container: binds the view model to presentational views and owns sheet/dialog state.
struct ContentView: View {
    @Bindable var model: BottleListViewModel
    @State private var showCreate = false
    @State private var restoreURL: URL?
    @State private var showDeleteConfirmation = false
    @State private var showCopy = false
    @State private var showInstall = false
    @State private var launcherProgram: URL?
    @State private var sidebar: SidebarItem? = .library

    var body: some View {
        NavigationSplitView {
            BottleSidebar(
                bottles: model.bottles, defaultName: model.defaultName, selection: $sidebar,
                onCreate: { showCreate = true }, onRestore: chooseArchive,
                onInstall: { showInstall = true; Task { await model.loadRecipes() } })
        } detail: {
            if sidebar == .library {
                LibraryView(
                    steamBottle: model.steamBottle, games: model.games, isBusy: model.isBusy,
                    isAvailable: model.isAvailable,
                    actions: .init(
                        installSteam: { Task { await model.installSteam() } },
                        openSteam: { Task { await model.openSteam() } },
                        refresh: { Task { await model.loadLibrary() } },
                        play: { game in Task { await model.play(game) } },
                        setGraphics: { game, backend in Task { await model.setGraphics(for: game, backend: backend) } },
                        setAutomaticGraphics: { game in Task { await model.setAutomaticGraphics(for: game) } },
                        addToDock: { game in Task { await model.addToDock(game) } }))
                    .task { await model.loadLibrary() }
            } else if let bottle = model.selectedBottle {
                BottleDetailView(
                    bottle: bottle, isDefault: model.isDefault(bottle),
                    prefixURL: model.prefixURL(for: bottle.name), isAvailable: model.isAvailable,
                    isBusy: model.isBusy,
                    actions: .init(
                        setGraphics: { backend in Task { await model.setGraphics(bottle.name, backend: backend) } },
                        setMSync: { on in Task { await model.setMSync(bottle.name, enabled: on) } },
                        makeDefault: { Task { await model.setDefault(bottle.name) } },
                        copy: { showCopy = true },
                        export: { exportBottle(bottle) },
                        delete: { showDeleteConfirmation = true },
                        runFile: chooseProgram,
                        createLauncher: { chooseLauncherProgram(in: bottle.name) },
                        drop: { urls in
                            guard let url = urls.first else { return false }
                            Task { await model.run(url, in: bottle.name) }
                            return true
                        }))
            } else {
                ContentUnavailableView("No bottle selected", systemImage: "wineglass",
                                       description: Text("Choose Library to play, or a bottle under Advanced."))
            }
        }
        .onChange(of: sidebar) { _, item in
            if case .bottle(let name) = item { model.selection = name } else { model.selection = nil }
        }
        .onChange(of: model.selection) { _, name in
            // Creating, copying or restoring a bottle selects it.
            if let name, sidebar != .bottle(name) { sidebar = .bottle(name) }
        }
        .overlay(alignment: .bottom) {
            if let message = model.busyMessage ?? model.launchMessage ?? (model.isBusy ? "Working…" : nil) {
                BusyBanner(message: message)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateBottleSheet { name, version, description in
                Task { await model.create(name: name, version: version, description: description) }
            }
        }
        .sheet(isPresented: $showCopy) {
            if let bottle = model.selectedBottle {
                NameSheet(title: "Copy “\(bottle.name)”", prompt: "New name", action: "Copy",
                          initial: bottle.name + " copy") { name in
                    Task { await model.copy(bottle.name, to: name) }
                }
            }
        }
        .sheet(isPresented: $showInstall) {
            InstallSheet(recipes: model.recipes, bottles: model.bottles.map(\.name)) { recipe, bottle in
                Task { await model.install(recipe: recipe, into: bottle) }
            }
        }
        .sheet(item: $launcherProgram) { program in
            NameSheet(title: "Create a launcher for “\(program.lastPathComponent)”", prompt: "App name", action: "Create",
                      initial: program.deletingPathExtension().lastPathComponent) { name in
                if let bottle = model.selection {
                    Task { await model.createLauncher(name: name, program: program, in: bottle) }
                }
            }
        }
        .onChange(of: model.lastLauncher) { _, app in
            if let app { NSWorkspace.shared.activateFileViewerSelecting([app]) }
        }
        .sheet(item: $restoreURL) { url in
            NameSheet(title: "Restore “\(url.lastPathComponent)”", prompt: "New name (optional)", action: "Restore",
                      initial: "", allowsEmpty: true) { name in
                Task { await model.restore(from: url, as: name.isEmpty ? nil : name) }
            }
        }
        .confirmationDialog("Delete this bottle?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let name = model.selection { Task { await model.delete(name) } }
            }
        } message: {
            Text("The bottle and everything installed in it will be removed. This cannot be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } })
        ) {
            Button("OK") { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private func chooseArchive() {
        let panel = NSOpenPanel()
        panel.message = "Choose an exported bottle archive"
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { restoreURL = panel.url }
    }

    private func chooseProgram() {
        guard let name = model.selection else { return }
        let panel = NSOpenPanel()
        panel.message = "Choose a program or document to open in “\(name)”"
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { Task { await model.run(url, in: name) } }
    }

    private func chooseLauncherProgram(in name: String) {
        let panel = NSOpenPanel()
        panel.message = "Choose the program in “\(name)” the launcher should open"
        panel.canChooseDirectories = false
        panel.directoryURL = model.prefixURL(for: name)?.appendingPathComponent("drive_c")
        if panel.runModal() == .OK { launcherProgram = panel.url }
    }

    private func exportBottle(_ bottle: Bottle) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(bottle.name).tar.gz"
        if panel.runModal() == .OK, let url = panel.url { Task { await model.export(bottle.name, to: url) } }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
