import Foundation
import Testing
@testable import BarrelAppKit

struct SettingsStoreTests {
    private func defaults() -> UserDefaults {
        let suite = "barrel-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func environmentSeedsUnsetValues() {
        let store = SettingsStore(defaults: defaults(), environment: [
            "BARREL_WINE": "/opt/wine/bin/wine", "BARREL_HOME": "/data", "BARREL_DXVK": "/dxvk"])
        let settings = store.load()
        #expect(settings.wineBinary == "/opt/wine/bin/wine")
        #expect(settings.dataDirectory.path == "/data")
        #expect(settings.components.dxvkDirectory?.path == "/dxvk")
        #expect(settings.components.dxmtDirectory == nil)
    }

    @Test func savedValuesWinOverEnvironment() {
        let defaults = defaults()
        let store = SettingsStore(defaults: defaults, environment: ["BARREL_WINE": "/env/wine"])
        var settings = store.load()
        settings.wineBinary = "/saved/wine"
        store.save(settings)
        #expect(store.load().wineBinary == "/saved/wine")
    }

    @Test func defaultDataDirectoryMatchesCLI() {
        let settings = SettingsStore(defaults: defaults(), environment: [:]).load()
        #expect(settings.dataDirectory.path.hasSuffix("Library/Application Support/Barrel"))
    }
}
