import BarrelAppKit
import SwiftUI

@main
struct BarrelApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        WindowGroup("Barrel") {
            ContentView(model: controller.bottles)
                .task { await controller.bottles.load() }
        }
        Settings {
            SettingsView(settings: controller.settings) { updated in
                Task { await controller.update(updated) }
            }
        }
    }
}
