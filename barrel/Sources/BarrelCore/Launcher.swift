import Foundation

/// A macOS app that opens one Windows program in a bottle through `barrel run`, or plays one Steam
/// game through `barrel play` (which applies the game's profile).
public struct LauncherSpec: Equatable, Sendable {
    public var name: String
    public var bottle: String
    /// Unix path of the program or document to open.
    public var program: String
    public var arguments: [String]
    /// When set, the launcher plays this Steam game instead of opening `program`.
    public var steamAppID: Int?
    /// Variables exported before `barrel` runs (BARREL_HOME, BARREL_WINE, …), since apps
    /// opened from Finder do not inherit the shell environment.
    public var environment: [String: String]
    public var barrelExecutable: URL

    public init(name: String, bottle: String, program: String, arguments: [String] = [],
                environment: [String: String] = [:], barrelExecutable: URL) {
        self.name = name
        self.bottle = bottle
        self.program = program
        self.arguments = arguments
        self.environment = environment
        self.barrelExecutable = barrelExecutable
    }

    public init(name: String, bottle: String, steamAppID: Int, environment: [String: String] = [:],
                barrelExecutable: URL) {
        self.init(name: name, bottle: bottle, program: "", environment: environment, barrelExecutable: barrelExecutable)
        self.steamAppID = steamAppID
    }
}

public enum LauncherError: Error, Equatable, CustomStringConvertible {
    case invalidName(String)
    case notFound(String)
    case foreignApp(String)

    public var description: String {
        switch self {
        case .invalidName(let name): "Invalid launcher name: '\(name)'"
        case .notFound(let name): "Launcher '\(name)' not found"
        case .foreignApp(let name): "'\(name).app' was not created by barrel; leaving it untouched"
        }
    }
}

/// Writes launcher app bundles (`<name>.app`) into one directory, e.g. ~/Applications/Barrel.
/// Only bundles it created (identifier `org.barrel.launcher.*`) are listed, replaced or removed.
public struct LauncherInstaller: Sendable {
    public let directory: URL
    /// Where each launcher appends its output (`<name>.log`); apps opened from Finder have no terminal.
    public let logDirectory: URL

    static let identifierPrefix = "org.barrel.launcher."

    public init(directory: URL,
                logDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/Barrel")) {
        self.directory = directory
        self.logDirectory = logDirectory
    }

    /// Creates or replaces the launcher. `icon` is ICNS data. The bundle is built next to its final
    /// place and swapped in, so a failure leaves any previous launcher intact.
    @discardableResult
    public func install(_ spec: LauncherSpec, icon: Data? = nil) throws -> URL {
        try validate(spec.name)
        let fileManager = FileManager.default
        let app = appURL(spec.name)
        let exists = fileManager.fileExists(atPath: app.path)
        if exists, !isBarrelLauncher(app) { throw LauncherError.foreignApp(spec.name) }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".\(UUID().uuidString).app", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let contents = staging.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)

        var info: [String: Any] = [
            "CFBundleName": spec.name,
            "CFBundleDisplayName": spec.name,
            "CFBundleExecutable": "launcher",
            "CFBundleIdentifier": Self.identifierPrefix + identifierSafe(spec.name),
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSApplicationCategoryType": "public.app-category.games",
        ]
        if let icon {
            let resources = contents.appendingPathComponent("Resources")
            try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
            try icon.write(to: resources.appendingPathComponent("AppIcon.icns"))
            info["CFBundleIconFile"] = "AppIcon"
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let executable = macOS.appendingPathComponent("launcher")
        try Data(script(for: spec).utf8).write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        if exists {
            _ = try fileManager.replaceItemAt(app, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: app)
        }
        return app
    }

    public func list() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".app") && !$0.hasPrefix(".") }
            .filter { isBarrelLauncher(directory.appendingPathComponent($0)) }
            .map { String($0.dropLast(4)) }
            .sorted()
    }

    public func remove(_ name: String) throws {
        try validate(name)
        let app = appURL(name)
        guard FileManager.default.fileExists(atPath: app.path) else { throw LauncherError.notFound(name) }
        guard isBarrelLauncher(app) else { throw LauncherError.foreignApp(name) }
        try FileManager.default.removeItem(at: app)
    }

    private func isBarrelLauncher(_ app: URL) -> Bool {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return (info?["CFBundleIdentifier"] as? String)?.hasPrefix(Self.identifierPrefix) == true
    }

    private func appURL(_ name: String) -> URL {
        directory.appendingPathComponent(name + ".app", isDirectory: true)
    }

    private func script(for spec: LauncherSpec) -> String {
        let log = logDirectory.appendingPathComponent(spec.name + ".log")
        var lines = ["#!/bin/sh", "# Generated by barrel.",
                     "mkdir -p \(shellQuoted(logDirectory.path))",
                     "exec >>\(shellQuoted(log.path)) 2>&1",
                     "echo \"--- $(date)\""]
        for (key, value) in spec.environment.sorted(by: { $0.key < $1.key }) {
            lines.append("export \(key)=\(shellQuoted(value))")
        }
        let command = if let appID = spec.steamAppID {
            [spec.barrelExecutable.path, "play", "--bottle", spec.bottle, String(appID)]
                + (spec.arguments.isEmpty ? [] : ["--"] + spec.arguments)
        } else {
            [spec.barrelExecutable.path, "run", "--bottle", spec.bottle, spec.program] + spec.arguments
        }
        lines.append("exec " + command.map(shellQuoted).joined(separator: " "))
        return lines.joined(separator: "\n") + "\n"
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private func identifierSafe(_ name: String) -> String {
        String(name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
    }

    private func validate(_ name: String) throws {
        let forbidden = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        guard !name.isEmpty, !name.hasPrefix("."), name.count <= 128,
              name.rangeOfCharacter(from: forbidden) == nil
        else { throw LauncherError.invalidName(name) }
    }
}
