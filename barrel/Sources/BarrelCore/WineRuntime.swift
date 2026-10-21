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

    public init(wineBinary: URL) {
        self.wineBinary = wineBinary
    }

    public func initializePrefix(at prefix: URL, environment: [String: String]) throws {
        try run(wineBinary, ["wineboot", "--init"], prefix: prefix, extraEnvironment: environment)
        try run(wineserver, ["-w"], prefix: prefix, extraEnvironment: environment)
    }

    public func setWindowsVersion(_ version: WindowsVersion, prefix: URL, environment: [String: String]) throws {
        try run(wineBinary, ["winecfg", "-v", version.winecfgName], prefix: prefix, extraEnvironment: environment)
        try run(wineserver, ["-w"], prefix: prefix, extraEnvironment: environment)
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
                extraEnvironment: environment, quiet: true)
    }

    private var wineserver: URL {
        wineBinary.deletingLastPathComponent().appendingPathComponent("wineserver")
    }

    @discardableResult
    private func run(_ executable: URL, _ arguments: [String], prefix: URL,
                     extraEnvironment: [String: String] = [:], allowFailure: Bool = false,
                     quiet: Bool = false) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if quiet { process.standardOutput = FileHandle.nullDevice }
        var environment = LaunchEnvironment.merge(extraEnvironment, into: ProcessInfo.processInfo.environment)
        environment["WINEPREFIX"] = prefix.path
        environment["WINEDEBUG"] = environment["WINEDEBUG"] ?? "-all"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 && !allowFailure {
            throw WineRuntimeError.commandFailed(
                command: ([executable.lastPathComponent] + arguments).joined(separator: " "),
                status: process.terminationStatus)
        }
        return process.terminationStatus
    }
}
