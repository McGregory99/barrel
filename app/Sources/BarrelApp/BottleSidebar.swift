import BarrelCore
import SwiftUI

struct BottleSidebar: View {
    let bottles: [Bottle]
    let defaultName: String?
    @Binding var selection: String?
    let onCreate: () -> Void
    let onRestore: () -> Void
    let onInstall: () -> Void

    var body: some View {
        List(bottles, id: \.name, selection: $selection) { bottle in
            HStack {
                Label(bottle.name, systemImage: "wineglass")
                Spacer()
                if bottle.name == defaultName {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).help("Default bottle")
                }
            }
        }
        // Wide enough for the sidebar toolbar (sidebar toggle + two actions) without an overflow menu.
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        .navigationTitle("Bottles")
        .toolbar {
            ToolbarItem {
                // Click creates a bottle; the menu also offers restoring one from an archive.
                Menu {
                    Button("New Bottle…", action: onCreate)
                    Button("Restore Bottle…", action: onRestore)
                } label: {
                    Label("New Bottle", systemImage: "plus")
                } primaryAction: {
                    onCreate()
                }
                .help("New Bottle")
            }
            ToolbarItem {
                Button(action: onInstall) { Label("Install Software…", systemImage: "shippingbox") }
                    .help("Install Software…")
            }
        }
    }
}
