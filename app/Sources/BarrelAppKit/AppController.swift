import Foundation
import Observation

/// Composition root state: settings plus the bottle view model wired to them.
@MainActor @Observable
public final class AppController {
    public private(set) var settings: AppSettings
    public let bottles: BottleListViewModel
    private let store: SettingsStore

    public init(store: SettingsStore = SettingsStore()) {
        self.store = store
        self.settings = store.load()
        self.bottles = BottleListViewModel(gateway: nil)
        rebuildGateway()
    }

    public func update(_ settings: AppSettings) async {
        self.settings = settings
        store.save(settings)
        rebuildGateway()
        await bottles.load()
    }

    private func rebuildGateway() {
        do {
            bottles.gateway = try BarrelCoreGateway(settings: settings)
        } catch {
            bottles.gateway = nil
            bottles.reportError(error)
        }
    }
}
