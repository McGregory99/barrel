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

    var body: some View {
        NavigationSplitView {
            BottleSidebar(
                bottles: model.bottles, defaultName: model.defaultName, selection: $model.selection,
                onCreate: { showCreate = true }, onRestore: chooseArchive)
        } detail: {
            if let bottle = model.selectedBottle {
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
                        drop: { urls in
                            guard let url = urls.first else { return false }
                            Task { await model.run(url, in: bottle.name) }
                            return true
                        }))
            } else {
                ContentUnavailableView("No bottle selected", systemImage: "wineglass",
                                       description: Text("Create or select a bottle."))
            }
        }
        .overlay(alignment: .bottom) { if let message = model.busyMessage ?? (model.isBusy ? "Working…" : nil) { BusyBanner(message: message) } }
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

    private func exportBottle(_ bottle: Bottle) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(bottle.name).tar.gz"
        if panel.runModal() == .OK, let url = panel.url { Task { await model.export(bottle.name, to: url) } }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
