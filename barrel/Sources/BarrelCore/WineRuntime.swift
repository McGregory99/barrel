import Foundation

/// Port for the Wine operations bottle management needs. Every call takes the bottle's
/// environment: a running wineserver rejects clients whose sync mode (WINEMSYNC) differs.
public protocol WineRuntime {
    func initializePrefix(at prefix: URL, environment: [String: String]) throws
    func setWindowsVersion(_ version: WindowsVersion, prefix: URL, environment: [String: String]) throws
    func shutdown(prefix: URL) throws
    /// Opens a program or document through Windows associations and waits for it; returns its exit status.
    func start(_ path: String, arguments: [String], prefix: URL, environment: [String: String]) throws -> Int32
    /// Writes a REG_SZ value into the prefix registry.
    func setRegistryValue(key: String, name: String, data: String, prefix: URL, environment: [String: String]) throws
    /// Removes a registry value; a value that does not exist is not an error.
    func deleteRegistryValue(key: String, name: String, prefix: URL, environment: [String: String]) throws
}

public enum WineRuntimeError: Error, Equatable, CustomStringConvertible {
    case commandFailed(command: String, status: Int32)

    public var description: String {
        switch self {
        case .commandFailed(let command, let status): "'\(command)' exited with status \(status)"
        }
    }
}

/// Runs a Wine build installed at `wineBinary` (its sibling `wineserver` is used for shutdown).
public struct ProcessWineRuntime: WineRuntime {
    public let wineBinary: URL
    /// Where a failed maintenance command's Wine output goes (it is hidden when the command succeeds).
    let diagnostics: FileHandle

    public init(wineBinary: URL, diagnostics: FileHandle = .standardError) {
        self.wineBinary = wineBinary
        self.diagnostics = diagnostics
    }

    public func initializePrefix(at prefix: URL, environment: [String: String]) throws {
        try run(wineBinary, ["wineboot", "--init"], prefix: prefix, extraEnvironment: environment, unattended: true)
        try run(wineserver, ["-w"], prefix: prefix, extraEnvironment: environment, unattended: true)
    }

    public func setWindowsVersion(_ version: WindowsVersion, prefix: URL, environment: [String: String]) throws {
        try run(wineBinary, ["winecfg", "-v", version.winecfgName], prefix: prefix, extraEnvironment: environment,
                unattended: true)
        try run(wineserver, ["-w"], prefix: prefix, extraEnvironment: environment, unattended: true)
    }

    public func shutdown(prefix: URL) throws {
        try run(wineserver, ["-k"], prefix: prefix, allowFailure: true)
    }

    public func start(_ path: String, arguments: [String], prefix: URL, environment: [String: String]) throws -> Int32 {
        try run(wineBinary, ["start", "/wait", "/unix", path] + arguments, prefix: prefix,
                extraEnvironment: environment, allowFailure: true)
    }

    public func setRegistryValue(key: String, name: String, data: String, prefix: URL,
                                 environment: [String: String]) throws {
        try run(wineBinary, ["reg", "add", key, "/v", name, "/t", "REG_SZ", "/d", data, "/f"], prefix: prefix,
                extraEnvironment: environment, quiet: true, unattended: true)
    }

    public func deleteRegistryValue(key: String, name: String, prefix: URL, environment: [String: String]) throws {
        // reg exits 1 when the value is already gone, which is the state we want.
        try run(wineBinary, ["reg", "delete", key, "/v", name, "/f"], prefix: prefix, extraEnvironment: environment,
                allowFailure: true, quiet: true, unattended: true)
    }

    private var wineserver: URL {
        wineBinary.deletingLastPathComponent().appendingPathComponent("wineserver")
    }

    /// Disabling mscoree/mshtml keeps a prefix creation or update (which any Wine command can
    /// trigger after a Wine upgrade) from opening the Wine Mono/Gecko installer dialogs and
    /// blocking a command nobody is watching.
    static let unattendedOverrides = "mscoree,mshtml="

    @discardableResult
    private func run(_ executable: URL, _ arguments: [String], prefix: URL,
                     extraEnvironment: [String: String] = [:], allowFailure: Bool = false,
                     quiet: Bool = false, unattended: Bool = false) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if quiet { process.standardOutput = FileHandle.nullDevice }
        var environment = LaunchEnvironment.merge(extraEnvironment, into: ProcessInfo.processInfo.environment)
        if unattended {
            environment["WINEDLLOVERRIDES"] = [environment["WINEDLLOVERRIDES"], Self.unattendedOverrides]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ";")
        }
        environment["WINEPREFIX"] = prefix.path
        environment["WINEDEBUG"] = environment["WINEDEBUG"] ?? "-all"
        // MoltenVK logs its whole feature list at the default level, on every Wine start.
        environment["MVK_CONFIG_LOG_LEVEL"] = environment["MVK_CONFIG_LOG_LEVEL"] ?? "1"
        process.environment = environment
        // Maintenance output (wineserver's msync banner, Wine fixme lines) is noise unless the command fails.
        let captured = unattended ? FileManager.default.temporaryDirectory
            .appendingPathComponent("barrel-wine-\(UUID().uuidString).log") : nil
        if let captured {
            FileManager.default.createFile(atPath: captured.path, contents: nil)
            process.standardError = try FileHandle(forWritingTo: captured)
        }
        defer { captured.map { try? FileManager.default.removeItem(at: $0) } }
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0, !allowFailure, let captured, let output = try? Data(contentsOf: captured) {
            diagnostics.write(output)
        }
        if process.terminationStatus != 0 && !allowFailure {
            throw WineRuntimeError.commandFailed(
                command: ([executable.lastPathComponent] + arguments).joined(separator: " "),
                status: process.terminationStatus)
        }
        return process.terminationStatus
    }
}
