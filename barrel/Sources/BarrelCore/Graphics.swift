import Foundation

/// Direct3D implementation a bottle uses.
public enum GraphicsBackend: String, Codable, CaseIterable, Sendable {
    /// Wine's builtin D3D → OpenGL translation.
    case wined3d
    /// D3D9–11 → Vulkan (MoltenVK → Metal).
    case dxvk
    /// D3D10/11 → Metal.
    case dxmt
    /// Apple Game Porting Toolkit, D3D11/12 → Metal. Not redistributable: user supplies it.
    case d3dmetal

    /// Wine load order for the Direct3D DLLs under this backend.
    var dllOverrideMode: String {
        switch self {
        case .wined3d, .d3dmetal: "builtin"
        case .dxvk, .dxmt: "native,builtin"
        }
    }

    /// D3DMetal needs process-wide environment (WINEDLLPATH), so it cannot be chosen per executable.
    var supportsPerApp: Bool { self != .d3dmetal }

    public init(name: String) throws {
        guard let backend = GraphicsBackend(rawValue: name.lowercased()) else {
            throw BottleError.unknownBackend(name)
        }
        self = backend
    }
}

/// Locations of optional runtime pieces outside the Wine install.
public struct RuntimeComponents: Sendable {
    /// Native libraries Wine loads by name, e.g. libMoltenVK.dylib.
    public var libraryDirectory: URL?
    /// DXVK build with `x64/` and `x32/` DLL folders.
    public var dxvkDirectory: URL?
    /// DXMT build with `x64/` and `x32/` DLL folders.
    public var dxmtDirectory: URL?
    /// Game Porting Toolkit root containing `wine/` and `external/` (D3DMetal.framework).
    public var gptkDirectory: URL?

    public init(libraryDirectory: URL? = nil, dxvkDirectory: URL? = nil,
                dxmtDirectory: URL? = nil, gptkDirectory: URL? = nil) {
        self.libraryDirectory = libraryDirectory
        self.dxvkDirectory = dxvkDirectory
        self.dxmtDirectory = dxmtDirectory
        self.gptkDirectory = gptkDirectory
    }

    public func isAvailable(_ backend: GraphicsBackend) -> Bool {
        switch backend {
        case .wined3d: true
        case .dxvk: dxvkDirectory != nil
        case .dxmt: dxmtDirectory != nil
        case .d3dmetal: gptkDirectory != nil
        }
    }
}

/// Port that prepares a prefix for a backend (e.g. copies replacement DLLs).
public protocol GraphicsInstaller {
    func install(_ backend: GraphicsBackend, into prefix: URL, components: RuntimeComponents) throws
}

/// Copies DXVK/DXMT DLLs into the prefix: `x64` → system32, `x32` → syswow64.
public struct FileGraphicsInstaller: GraphicsInstaller {
    public init() {}

    public func install(_ backend: GraphicsBackend, into prefix: URL, components: RuntimeComponents) throws {
        let source: URL?
        switch backend {
        case .dxvk: source = components.dxvkDirectory
        case .dxmt: source = components.dxmtDirectory
        case .wined3d, .d3dmetal: source = nil
        }
        guard let source else { return }

        let windows = prefix.appendingPathComponent("drive_c/windows")
        try copyDLLs(from: source.appendingPathComponent("x64"), to: windows.appendingPathComponent("system32"))
        try copyDLLs(from: source.appendingPathComponent("x32"), to: windows.appendingPathComponent("syswow64"))
    }

    private func copyDLLs(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in try fileManager.contentsOfDirectory(atPath: source.path) where name.hasSuffix(".dll") {
            let target = destination.appendingPathComponent(name)
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.copyItem(at: source.appendingPathComponent(name), to: target)
        }
    }
}

/// Environment variables Wine needs to run a bottle with its selected options.
/// Direct3D DLL load order lives in the prefix registry (see `BottleService.setGraphics`),
/// so per-executable AppDefaults can override it; the environment would win over both.
public enum LaunchEnvironment {
    static let direct3DLibraries = ["d3d9", "d3d10core", "d3d11", "dxgi"]
    static let systemLibraryFallback = ["/usr/local/lib", "/usr/lib"]

    public static func make(for bottle: Bottle, components: RuntimeComponents) -> [String: String] {
        var env: [String: String] = ["CX_ACTIVE_GRAPHICS_BACKEND": bottle.graphicsBackend.rawValue]
        var libraryPath = components.libraryDirectory.map { [$0.path] } ?? []

        if bottle.graphicsBackend == .d3dmetal, let gptk = components.gptkDirectory {
            let external = gptk.appendingPathComponent("external").path
            env["WINEDLLPATH"] = gptk.appendingPathComponent("wine").path
            env["DYLD_FALLBACK_FRAMEWORK_PATH"] = external
            libraryPath.append(external)
        }

        if !libraryPath.isEmpty {
            env["DYLD_FALLBACK_LIBRARY_PATH"] = (libraryPath + systemLibraryFallback).joined(separator: ":")
        }
        if bottle.msync {
            env["WINEMSYNC"] = "1"
        }
        return env
    }

    /// Applies `bottle` variables over `base`. `WINEDLLOVERRIDES` is combined, not replaced,
    /// so caller overrides (e.g. `mscoree,mshtml=` to skip Mono/Gecko) survive.
    public static func merge(_ bottle: [String: String], into base: [String: String]) -> [String: String] {
        var merged = base.merging(bottle) { _, new in new }
        if let callerOverrides = base["WINEDLLOVERRIDES"], !callerOverrides.isEmpty,
           let bottleOverrides = bottle["WINEDLLOVERRIDES"] {
            merged["WINEDLLOVERRIDES"] = "\(callerOverrides);\(bottleOverrides)"
        }
        return merged
    }
}
