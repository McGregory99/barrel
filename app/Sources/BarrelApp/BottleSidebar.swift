import BarrelCore
import SwiftUI

/// What the sidebar can show: the Steam library, or one bottle (Advanced).
enum SidebarItem: Hashable {
    case library
    case bottle(String)
}

struct BottleSidebar: View {
    let bottles: [Bottle]
    let defaultName: String?
    @Binding var selection: SidebarItem?
    let onCreate: () -> Void
    let onRestore: () -> Void
    let onInstall: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Play") {
                Label("Library", systemImage: "gamecontroller").tag(SidebarItem.library)
            }
            Section {
                ForEach(bottles, id: \.name) { bottle in
                    HStack {
                        Label(bottle.name, systemImage: "wineglass")
                        Spacer()
                        if bottle.name == defaultName {
                            Image(systemName: "star.fill").foregroundStyle(.yellow).help("Default bottle")
                        }
                    }
                    .tag(SidebarItem.bottle(bottle.name))
                }
            } header: {
                HStack {
                    Text("Advanced")
                    Spacer()
                    Menu {
                        Button("New Bottle…", action: onCreate)
                        Button("Install Software…", action: onInstall)
                        Button("Restore Bottle…", action: onRestore)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Bottles: create, install software, restore")
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }
}
