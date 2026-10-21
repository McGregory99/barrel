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
