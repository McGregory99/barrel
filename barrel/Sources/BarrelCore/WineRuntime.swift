import Foundation

/// Port for the Wine operations bottle management needs.
public protocol WineRuntime {
    func initializePrefix(at prefix: URL) throws
    func setWindowsVersion(_ version: WindowsVersion, prefix: URL) throws
    func shutdown(prefix: URL) throws
    /// Opens a program or document through Windows associations and waits for it; returns its exit status.
    func start(_ path: String, arguments: [String], prefix: URL) throws -> Int32
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

    public func initializePrefix(at prefix: URL) throws {
        try run(wineBinary, ["wineboot", "--init"], prefix: prefix)
        try run(wineserver, ["-w"], prefix: prefix)
    }

    public func setWindowsVersion(_ version: WindowsVersion, prefix: URL) throws {
        try run(wineBinary, ["winecfg", "-v", version.winecfgName], prefix: prefix)
        try run(wineserver, ["-w"], prefix: prefix)
    }

    public func shutdown(prefix: URL) throws {
        try run(wineserver, ["-k"], prefix: prefix, allowFailure: true)
    }

    public func start(_ path: String, arguments: [String], prefix: URL) throws -> Int32 {
        try run(wineBinary, ["start", "/wait", "/unix", path] + arguments, prefix: prefix, allowFailure: true)
    }

    private var wineserver: URL {
        wineBinary.deletingLastPathComponent().appendingPathComponent("wineserver")
    }

    @discardableResult
    private func run(_ executable: URL, _ arguments: [String], prefix: URL, allowFailure: Bool = false) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
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
