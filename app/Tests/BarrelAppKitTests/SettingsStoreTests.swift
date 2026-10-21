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

    @Test func recipeFoldersComeFromSettingsThenDataDirectory() {
        let settings = SettingsStore(defaults: defaults(), environment: [
            "BARREL_HOME": "/data", "BARREL_RECIPES": "/repo/recipes"]).load()
        #expect(settings.recipeDirectories.map(\.path) == ["/repo/recipes", "/data/Recipes"])

        let plain = SettingsStore(defaults: defaults(), environment: ["BARREL_HOME": "/data"]).load()
        #expect(plain.recipeDirectories.map(\.path) == ["/data/Recipes"])
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

struct BundledRuntimeSettingsTests {
    private func defaults() -> UserDefaults {
        let suite = "barrel-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    let bundle = URL(fileURLWithPath: "/Applications/Barrel.app/Contents/Resources")

    @Test func bundledRuntimeFillsUnsetValues() {
        let settings = SettingsStore(defaults: defaults(), environment: [:], bundleResources: bundle).load()
        #expect(settings.wineBinary == bundle.path + "/runtime/wine/bin/wine")
        #expect(settings.librariesDirectory == bundle.path + "/runtime/deps/lib")
        #expect(settings.dxvkDirectory == bundle.path + "/runtime/dxvk")
        #expect(settings.dxmtDirectory == bundle.path + "/runtime/dxmt")
        #expect(settings.recipesDirectory == bundle.path + "/recipes")
        #expect(settings.gptkDirectory == "")
    }

    @Test func environmentAndSavedValuesWinOverTheBundle() {
        let defaults = defaults()
        let store = SettingsStore(defaults: defaults, environment: ["BARREL_WINE": "/env/wine"], bundleResources: bundle)
        #expect(store.load().wineBinary == "/env/wine")
        var settings = store.load()
        settings.dxvkDirectory = "/saved/dxvk"
        store.save(settings)
        #expect(store.load().dxvkDirectory == "/saved/dxvk")
    }

    @Test func emptySavedValuesCountAsUnset() {
        let defaults = defaults()
        let store = SettingsStore(defaults: defaults, environment: [:], bundleResources: bundle)
        var settings = AppSettings()
        settings.wineBinary = ""
        store.save(settings)
        #expect(store.load().wineBinary == bundle.path + "/runtime/wine/bin/wine")
    }
}
