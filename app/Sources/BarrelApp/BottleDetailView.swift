import BarrelCore
import SwiftUI
import UniformTypeIdentifiers

struct BottleActions {
    var setGraphics: (GraphicsBackend) -> Void
    var setMSync: (Bool) -> Void
    var makeDefault: () -> Void
    var copy: () -> Void
    var export: () -> Void
    var delete: () -> Void
    var runFile: () -> Void
    var drop: ([URL]) -> Bool
}

struct BottleDetailView: View {
    let bottle: Bottle
    let isDefault: Bool
    let prefixURL: URL?
    let isAvailable: (GraphicsBackend) -> Bool
    let isBusy: Bool
    let actions: BottleActions
    @State private var isDropTargeted = false

    var body: some View {
        Form {
            Section("Details") {
                LabeledContent("Windows version", value: bottle.windowsVersion.rawValue)
                LabeledContent("Created", value: bottle.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let description = bottle.description, !description.isEmpty {
                    LabeledContent("Description", value: description)
                }
                if let prefixURL {
                    LabeledContent("Prefix") {
                        HStack {
                            Text(prefixURL.path).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([prefixURL]) }
                        }
                    }
                }
            }
            Section("Graphics") {
                Picker("Backend", selection: Binding(get: { bottle.graphicsBackend }, set: actions.setGraphics)) {
                    ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                        Text(isAvailable(backend) ? backend.rawValue : "\(backend.rawValue) (not installed)")
                            .tag(backend)
                            .selectionDisabled(!isAvailable(backend))
                    }
                }
                if GraphicsBackend.allCases.contains(where: { !isAvailable($0) }) {
                    Text("Backends marked “not installed” need their component path set in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("MSync (faster synchronization)", isOn: Binding(get: { bottle.msync }, set: actions.setMSync))
            }
            Section("Programs") {
                Button("Run Program or Open Document…", action: actions.runFile)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isDropTargeted ? Color.accentColor : .secondary, style: StrokeStyle(lineWidth: 1, dash: [5]))
                    .frame(height: 60)
                    .overlay(Text("Drop .exe, .msi, .lnk or documents here").foregroundStyle(.secondary))
                    .dropDestination(for: URL.self, action: { urls, _ in actions.drop(urls) },
                                     isTargeted: { isDropTargeted = $0 })
            }
        }
        .formStyle(.grouped)
        .disabled(isBusy)
        .navigationTitle(bottle.name)
        .toolbar {
            ToolbarItemGroup {
                Button(action: actions.makeDefault) {
                    Label("Set as Default", systemImage: isDefault ? "star.fill" : "star")
                }.disabled(isDefault)
                Button(action: actions.copy) { Label("Copy…", systemImage: "doc.on.doc") }
                Button(action: actions.export) { Label("Export…", systemImage: "square.and.arrow.up") }
                Button(role: .destructive, action: actions.delete) { Label("Delete", systemImage: "trash") }
            }
        }
    }
}
