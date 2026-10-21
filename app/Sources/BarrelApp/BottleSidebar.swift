import BarrelCore
import SwiftUI

struct BottleSidebar: View {
    let bottles: [Bottle]
    let defaultName: String?
    @Binding var selection: String?
    let onCreate: () -> Void
    let onRestore: () -> Void

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
        .navigationTitle("Bottles")
        .toolbar {
            ToolbarItem {
                Button(action: onCreate) { Label("New Bottle", systemImage: "plus") }
            }
            ToolbarItem {
                Button(action: onRestore) { Label("Restore Bottle…", systemImage: "arrow.down.doc") }
            }
        }
    }
}
