import Foundation

public enum SteamAppInfoError: Error, Equatable {
    case unsupportedVersion(UInt32)
    case truncated
}

/// Steam's app metadata cache (`appcache/appinfo.vdf`): for every app the client has seen, its
/// name, type, artwork hashes and more, as binary KeyValues. Versions 28 (keys inline) and 29 (keys
/// in a string table at the end of the file) are supported.
public enum SteamAppInfo {
    /// The entries of `appIDs`, keyed by app id; each value is the entry's root block
    /// (`appinfo` → `common` → `name`, `type`, …). Numbers come back as decimal strings.
    public static func parse(_ data: Data, appIDs: Set<Int>) throws -> [Int: KeyValues] {
        var reader = Reader(bytes: [UInt8](data))
        let magic = try reader.u32()
        guard magic & 0xFFFF_FF00 == 0x0756_4400, (0x28...0x29).contains(magic & 0xFF) else {
            throw SteamAppInfoError.unsupportedVersion(magic)
        }
        let version = magic & 0xFF
        _ = try reader.u32()  // universe
        var strings: [String]?
        if version >= 0x29 {
            var table = Reader(bytes: reader.bytes, index: Int(try reader.u64()))
            let count = try table.u32()
            strings = try (0..<count).map { _ in try table.cString() }
        }
        var result: [Int: KeyValues] = [:]
        while true {
            let appID = Int(try reader.u32())
            if appID == 0 { break }
            let size = Int(try reader.u32())
            let end = reader.index + size
            guard size >= 60, end <= reader.bytes.count else { throw SteamAppInfoError.truncated }
            if appIDs.contains(appID) {
                // Info state, last update, PICS token, SHA-1, change number, binary SHA-1.
                var entry = Reader(bytes: reader.bytes, index: reader.index + 60, end: end)
                result[appID] = .block(try entry.block(strings: strings))
            }
            reader.index = end
        }
        return result
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        var end: Int

        init(bytes: [UInt8], index: Int = 0, end: Int? = nil) {
            self.bytes = bytes
            self.index = index
            self.end = end ?? bytes.count
        }

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard index >= 0, count <= end - index else { throw SteamAppInfoError.truncated }
            defer { index += count }
            return bytes[index..<index + count]
        }

        mutating func u32() throws -> UInt32 {
            try take(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func u64() throws -> UInt64 {
            try take(8).reversed().reduce(0) { $0 << 8 | UInt64($1) }
        }

        mutating func cString() throws -> String {
            guard let zero = bytes[index..<end].firstIndex(of: 0) else { throw SteamAppInfoError.truncated }
            defer { index = zero + 1 }
            return String(decoding: bytes[index..<zero], as: UTF8.self)
        }

        /// Binary KeyValues up to the end-of-block marker (8).
        mutating func block(strings: [String]?) throws -> [(String, KeyValues)] {
            var entries: [(String, KeyValues)] = []
            while true {
                let type = try take(1).first!
                if type == 8 { return entries }
                let key: String
                if let strings {
                    let i = Int(try u32())
                    guard i < strings.count else { throw SteamAppInfoError.truncated }
                    key = strings[i]
                } else {
                    key = try cString()
                }
                switch type {
                case 0: entries.append((key, .block(try block(strings: strings))))
                case 1: entries.append((key, .string(try cString())))
                case 2: entries.append((key, .string(String(Int32(bitPattern: try u32())))))
                case 3: entries.append((key, .string(String(Float(bitPattern: try u32())))))
                case 4, 6: entries.append((key, .string(String(try u32()))))  // pointer, color
                case 7: entries.append((key, .string(String(try u64()))))
                case 10: entries.append((key, .string(String(Int64(bitPattern: try u64())))))
                default: throw SteamAppInfoError.truncated  // a type this reader does not know
                }
            }
        }
    }
}
