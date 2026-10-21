import BarrelAppKit
import SwiftUI

struct SettingsView: View {
    @State private var draft: AppSettings
    let onApply: (AppSettings) -> Void

    init(settings: AppSettings, onApply: @escaping (AppSettings) -> Void) {
        _draft = State(initialValue: settings)
        self.onApply = onApply
    }

    var body: some View {
        Form {
            PathField(title: "Wine binary", placeholder: "wine from PATH", text: $draft.wineBinary, directory: false)
            PathField(title: "Data directory", placeholder: AppSettings.defaultDataDirectory.path,
                      text: Binding(get: { draft.dataDirectory.path },
                                    set: { draft.dataDirectory = URL(fileURLWithPath: $0, isDirectory: true) }),
                      directory: true)
            PathField(title: "Native libraries", placeholder: "libMoltenVK.dylib folder", text: $draft.librariesDirectory, directory: true)
            PathField(title: "DXVK", placeholder: "folder with x64/ and x32/", text: $draft.dxvkDirectory, directory: true)
            PathField(title: "DXMT", placeholder: "folder with x64/ and x32/", text: $draft.dxmtDirectory, directory: true)
            PathField(title: "Game Porting Toolkit", placeholder: "your own copy (wine/, external/)", text: $draft.gptkDirectory, directory: true)
            HStack {
                Spacer()
                Button("Apply") { onApply(draft) }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding()
    }
}

struct PathField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let directory: Bool

    var body: some View {
        LabeledContent(title) {
            HStack {
                TextField("", text: $text, prompt: Text(placeholder)).textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = directory
                    panel.canChooseFiles = !directory
                    if panel.runModal() == .OK, let url = panel.url { text = url.path }
                }
            }
        }
    }
}
