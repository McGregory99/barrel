import BarrelCore
import Foundation

/// Errors raised while parsing, validating or resolving recipes.
public enum RecipeError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case unsupportedFormatVersion(Int)
    case missingField(String)
    case invalidValue(field: String, reason: String)
    case unknownStepKind(kind: String, step: Int)
    case missingSHA256(step: Int)
    case invalidSHA256(step: Int, value: String)
    case unknownDownloadReference(file: String, step: Int)
    case unknownRecipe(String)
    case unknownDependency(recipe: String, dependency: String)
    case dependencyCycle([String])
    case hashMismatch(file: String, expected: String, actual: String)
    case downloadFailed(url: String, reason: String)
    case stepFailed(recipe: String, step: Int, reason: String)

    public var description: String {
        switch self {
        case .invalidJSON(let reason): "Recipe is not valid JSON: \(reason)"
        case .unsupportedFormatVersion(let v): "Unsupported formatVersion \(v) (this build reads version 1)"
        case .missingField(let field): "Missing required field '\(field)'"
        case .invalidValue(let field, let reason): "Invalid value for '\(field)': \(reason)"
        case .unknownStepKind(let kind, let step):
            "Step \(step): unknown step kind '\(kind)'. Valid: download, run, registry, dllOverride"
        case .missingSHA256(let step): "Step \(step): download needs a 'sha256' (downloads are always verified)"
        case .invalidSHA256(let step, let value):
            "Step \(step): '\(value)' is not a valid SHA-256 (expected 64 hexadecimal characters)"
        case .unknownDownloadReference(let file, let step):
            "Step \(step): run refers to '\(file)', which no earlier download step provides"
        case .unknownRecipe(let id): "Recipe '\(id)' not found"
        case .unknownDependency(let recipe, let dep): "Recipe '\(recipe)' depends on unknown recipe '\(dep)'"
        case .dependencyCycle(let path): "Dependency cycle: " + path.joined(separator: " -> ")
        case .hashMismatch(let file, let expected, let actual):
            "SHA-256 mismatch for '\(file)': expected \(expected), got \(actual)"
        case .downloadFailed(let url, let reason): "Download of \(url) failed: \(reason)"
        case .stepFailed(let recipe, let step, let reason): "Recipe '\(recipe)', step \(step) failed: \(reason)"
        }
    }
}

/// Bottle settings a recipe asks for. Absent fields leave the bottle untouched.
public struct BottleSettings: Equatable, Sendable {
    public var windowsVersion: WindowsVersion?
    public var graphicsBackend: GraphicsBackend?
    public var msync: Bool?
    /// Per-executable backends, applied after `graphicsBackend` (e.g. steamwebhelper.exe → wined3d).
    public var appGraphics: [String: GraphicsBackend]

    public init(windowsVersion: WindowsVersion? = nil, graphicsBackend: GraphicsBackend? = nil, msync: Bool? = nil,
                appGraphics: [String: GraphicsBackend] = [:]) {
        self.windowsVersion = windowsVersion
        self.graphicsBackend = graphicsBackend
        self.msync = msync
        self.appGraphics = appGraphics
    }
}

public enum DLLOverrideMode: String, Equatable, Sendable, CaseIterable {
    case native, builtin
    case nativeBuiltin = "native,builtin"
    case builtinNative = "builtin,native"
    case disabled

    /// Value stored in `HKCU\Software\Wine\DllOverrides` (empty string disables the DLL).
    public var registryData: String { self == .disabled ? "" : rawValue }
}

public enum RegistryType: String, Equatable, Sendable {
    case string = "REG_SZ"
    case dword = "REG_DWORD"
}

public struct DownloadStep: Equatable, Sendable {
    public var url: URL
    public var sha256: String
    public var fileName: String
}

public struct RunStep: Equatable, Sendable {
    /// File name of an earlier download step, or nil when `path` is used.
    public var file: String?
    /// Unix path or Windows path (`C:\...`).
    public var path: String?
    public var arguments: [String]
    public var expectedExitCodes: [Int32]
}

public struct RegistryStep: Equatable, Sendable {
    public var key: String
    public var name: String
    public var type: RegistryType
    public var data: String
}

public struct DLLOverrideStep: Equatable, Sendable {
    public var dll: String
    public var mode: DLLOverrideMode
}

public enum Step: Equatable, Sendable {
    case download(DownloadStep)
    case run(RunStep)
    case registry(RegistryStep)
    case dllOverride(DLLOverrideStep)
}

public struct Recipe: Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String?
    public var bottle: BottleSettings
    public var dependencies: [String]
    public var steps: [Step]
}
