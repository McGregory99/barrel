import Foundation

/// A game Steam has fully installed in a bottle.
public struct SteamGame: Equatable, Sendable {
    public var appID: Int
    public var name: String
    /// The game's folder (`steamapps/common/<installdir>`), as a macOS path.
    public var installDirectory: URL

    public init(appID: Int, name: String, installDirectory: URL) {
        self.appID = appID
        self.name = name
        self.installDirectory = installDirectory
    }
}

/// A game in the player's Steam library that is not installed in the bottle.
public struct SteamLibraryGame: Equatable, Sendable {
    public var appID: Int
    public var name: String
    /// Steam's small square icon for the game, when it has cached one.
    public var icon: URL?
    /// Larger cached artwork (capsule, header or logo), when there is no icon.
    public var artwork: URL?

    public init(appID: Int, name: String, icon: URL? = nil, artwork: URL? = nil) {
        self.appID = appID
        self.name = name
        self.icon = icon
        self.artwork = artwork
    }
}

/// Reads the Windows Steam client's library files inside a Wine prefix.
public enum SteamLibrary {
    /// Steam apps that are not games (Steamworks Common Redistributables).
    static let tools: Set<Int> = [228980]
    /// `StateFlags` bit Steam sets once an app is fully installed.
    static let fullyInstalled = 4

    public static func steamDirectory(prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }

    /// Fully installed games from every Steam library folder, sorted by name.
    public static func installedGames(prefix: URL) -> [SteamGame] {
        var games: [Int: SteamGame] = [:]
        for library in libraries(prefix: prefix) {
            let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: steamapps.path)) ?? []
            for file in files where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
                guard let text = try? String(contentsOf: steamapps.appendingPathComponent(file), encoding: .utf8),
                      let state = (try? KeyValues.parse(text))?["AppState"],
                      let appID = state["appid"]?.string.flatMap(Int.init), !tools.contains(appID),
                      let flags = state["StateFlags"]?.string.flatMap(Int.init), flags & fullyInstalled != 0,
                      let name = state["name"]?.string, let installdir = state["installdir"]?.string
                else { continue }
                games[appID] = SteamGame(
                    appID: appID, name: name,
                    installDirectory: steamapps.appendingPathComponent("common/\(installdir)", isDirectory: true))
            }
        }
        return games.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.appID < $1.appID : order == .orderedAscending
        }
    }

    /// Games in the player's library that are not installed, sorted by name, read offline.
    ///
    /// Steam keeps artwork in `appcache/librarycache/<appid>/` for the apps its library shows
    /// (owned, free or family-shared); `appcache/appinfo.vdf` gives each app's name and type. Only
    /// apps of type "game" are kept, so tools, soundtracks and redistributables drop out. Steam
    /// writes both caches itself, so the list is as fresh as Steam's last look at the library.
    public static func uninstalledGames(prefix: URL) -> [SteamLibraryGame] {
        let appcache = steamDirectory(prefix: prefix).appendingPathComponent("appcache", isDirectory: true)
        let cache = appcache.appendingPathComponent("librarycache", isDirectory: true)
        let installed = Set(installedGames(prefix: prefix).map(\.appID))
        let cached = Set(((try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? [])
            .compactMap(Int.init)).subtracting(installed).subtracting(tools)
        guard !cached.isEmpty,
              let data = try? Data(contentsOf: appcache.appendingPathComponent("appinfo.vdf"), options: .alwaysMapped),
              let apps = try? SteamAppInfo.parse(data, appIDs: cached)
        else { return [] }
        let games = apps.compactMap { appID, root -> SteamLibraryGame? in
            guard let common = root["appinfo"]?["common"], common["type"]?.string?.lowercased() == "game",
                  let name = common["name"]?.string, !name.isEmpty else { return nil }
            let folder = cache.appendingPathComponent(String(appID), isDirectory: true)
            let icon = ["icon", "clienticon"].lazy.compactMap { common[$0]?.string }
                .map { folder.appendingPathComponent("\($0).jpg") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            return SteamLibraryGame(appID: appID, name: name, icon: icon, artwork: artwork(in: folder))
        }
        return games.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.appID < $1.appID : order == .orderedAscending
        }
    }

    /// Cached artwork names, best first. Newer clients keep each one in a hash-named subfolder.
    static let artworkNames = ["library_capsule.jpg", "library_600x900.jpg", "header.jpg", "library_header.jpg",
                               "logo.png"]

    static func artwork(in folder: URL) -> URL? {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return nil }
        var found: [String: URL] = [:]
        for case let url as URL in walker {
            if walker.level > 2 { walker.skipDescendants(); continue }
            if artworkNames.contains(url.lastPathComponent) { found[url.lastPathComponent] = url }
        }
        return artworkNames.lazy.compactMap { found[$0] }.first
    }

    /// The default library plus those listed in `libraryfolders.vdf`, without duplicates.
    static func libraries(prefix: URL) -> [URL] {
        let steam = steamDirectory(prefix: prefix)
        var result = [steam]
        let vdf = steam.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: vdf, encoding: .utf8),
           let folders = (try? KeyValues.parse(text))?["libraryfolders"]?.children {
            for (_, folder) in folders {
                if let path = folder["path"]?.string, let url = unixPath(windowsPath: path, prefix: prefix) {
                    result.append(url)
                }
            }
        }
        // Resolve Wine's drive symlinks so each library is listed once, under its real folder.
        var seen = Set<String>()
        return result.map { $0.resolvingSymlinksInPath() }.filter { seen.insert($0.path).inserted }
    }

    /// `D:\Games` → `<prefix>/dosdevices/d:/Games`, which Wine maps to the real folder.
    static func unixPath(windowsPath: String, prefix: URL) -> URL? {
        let parts = windowsPath.split(separator: "\\", omittingEmptySubsequences: true).map(String.init)
        guard let drive = parts.first, drive.count == 2, drive.hasSuffix(":") else { return nil }
        var url = prefix.appendingPathComponent("dosdevices/\(drive.lowercased())", isDirectory: true)
        for part in parts.dropFirst() { url.appendPathComponent(part, isDirectory: true) }
        return url
    }

    /// Executables that ship with games but are not the game.
    static let helperNames = ["crashhandler", "crashreport", "unins", "redist", "dxsetup", "vcredist",
                              "dotnet", "directx", "setup", "easyanticheat", "uploader"]

    /// Best guess at the executable that renders the game: an Unreal `*-Shipping.exe`, else an `.exe`
    /// named like the game, else the largest one. Helpers (crash handlers, uninstallers,
    /// redistributables) are ignored.
    public static func mainExecutable(of game: SteamGame) -> URL? {
        guard let walker = FileManager.default.enumerator(
            at: game.installDirectory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return nil }
        var candidates: [(url: URL, size: Int)] = []
        for case let url as URL in walker {
            if walker.level > 4 { walker.skipDescendants(); continue }
            let lower = url.lastPathComponent.lowercased()
            // The name becomes part of a registry key path, so it must not contain a separator.
            guard lower.hasSuffix(".exe"), !lower.contains("\\"), !helperNames.contains(where: lower.contains)
            else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            candidates.append((url, values?.fileSize ?? 0))
        }
        func simple(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        let names = [simple(game.name), simple(game.installDirectory.lastPathComponent)]
        if let shipping = candidates.first(where: { $0.url.lastPathComponent.hasSuffix("-Shipping.exe") }) {
            return shipping.url
        }
        if let named = candidates.first(where: { names.contains(simple($0.url.deletingPathExtension().lastPathComponent)) }) {
            return named.url
        }
        return candidates.max { $0.size < $1.size }?.url
    }
}

public enum KeyValuesError: Error, Equatable {
    case unexpectedEnd
    case unexpected(Character)
}

/// Valve's KeyValues text format (`.vdf`, `.acf`): quoted keys followed by a quoted value or a
/// `{ … }` block.
public indirect enum KeyValues: Equatable, Sendable {
    case string(String)
    case block([(String, KeyValues)])

    public static func == (a: KeyValues, b: KeyValues) -> Bool {
        switch (a, b) {
        case let (.string(x), .string(y)): x == y
        case let (.block(x), .block(y)): x.map(\.0) == y.map(\.0) && zip(x, y).allSatisfy { $0.1 == $1.1 }
        default: false
        }
    }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var children: [(String, KeyValues)] { if case .block(let c) = self { c } else { [] } }

    /// The first child with this key (Steam's keys are case-insensitive).
    public subscript(key: String) -> KeyValues? {
        children.first { $0.0.caseInsensitiveCompare(key) == .orderedSame }?.1
    }

    public static func parse(_ text: String) throws -> KeyValues {
        var scanner = Scanner(Array(text))
        let root = try scanner.block(topLevel: true)
        return .block(root)
    }

    private struct Scanner {
        let chars: [Character]
        var index = 0
        init(_ chars: [Character]) { self.chars = chars }

        mutating func skipSpaceAndComments() {
            while index < chars.count {
                if chars[index].isWhitespace {
                    index += 1
                } else if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                    while index < chars.count, chars[index] != "\n" { index += 1 }
                } else {
                    return
                }
            }
        }

        mutating func block(topLevel: Bool) throws -> [(String, KeyValues)] {
            var entries: [(String, KeyValues)] = []
            while true {
                skipSpaceAndComments()
                guard index < chars.count else {
                    if topLevel { return entries }
                    throw KeyValuesError.unexpectedEnd
                }
                if chars[index] == "}" {
                    if topLevel { throw KeyValuesError.unexpected("}") }
                    index += 1
                    return entries
                }
                let key = try token()
                skipSpaceAndComments()
                guard index < chars.count else { throw KeyValuesError.unexpectedEnd }
                if chars[index] == "{" {
                    index += 1
                    entries.append((key, .block(try block(topLevel: false))))
                } else {
                    entries.append((key, .string(try token())))
                }
            }
        }

        /// A quoted string with `\\`, `\"`, `\n` and `\t` escapes, or a bare word.
        mutating func token() throws -> String {
            guard index < chars.count else { throw KeyValuesError.unexpectedEnd }
            if chars[index] == "{" || chars[index] == "}" { throw KeyValuesError.unexpected(chars[index]) }
            var result = ""
            if chars[index] == "\"" {
                index += 1
                while index < chars.count, chars[index] != "\"" {
                    if chars[index] == "\\", index + 1 < chars.count {
                        index += 1
                        switch chars[index] {
                        case "n": result.append("\n")
                        case "t": result.append("\t")
                        default: result.append(chars[index])
                        }
                    } else {
                        result.append(chars[index])
                    }
                    index += 1
                }
                guard index < chars.count else { throw KeyValuesError.unexpectedEnd }
                index += 1
            } else {
                while index < chars.count, !chars[index].isWhitespace, !"{}\"".contains(chars[index]) {
                    result.append(chars[index])
                    index += 1
                }
            }
            return result
        }
    }
}
