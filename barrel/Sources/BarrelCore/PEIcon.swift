import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PEIconError: Error, Equatable, CustomStringConvertible {
    case notPortableExecutable
    case malformed
    case unreadableImage

    public var description: String {
        switch self {
        case .notPortableExecutable: "Not a Windows executable"
        case .malformed: "The executable's icon resources are damaged"
        case .unreadableImage: "The icon image could not be read"
        }
    }
}

/// Reads the application icon from a Windows PE file (the first RT_GROUP_ICON, as Explorer shows it).
/// The input is untrusted: every offset is bounds-checked.
public enum PEIcon {
    static let rtIcon: UInt32 = 3
    static let rtGroupIcon: UInt32 = 14

    /// Returns a single-image `.ico` file with the group's largest, most colorful image, or nil
    /// when the executable has no icon.
    public static func largestIcon(in data: Data) throws -> Data? {
        let reader = Reader(data)
        guard let resources = try resourceSection(reader) else { return nil }

        guard let groupData = try firstResource(type: rtGroupIcon, id: nil, resources: resources, reader: reader)
        else { return nil }
        let group = Reader(groupData)
        let count = Int(try group.u16(4))
        var best: (width: Int, bits: Int, id: UInt16, entry: Data)?
        for index in 0..<count {
            let entry = 6 + index * 14
            let rawWidth = Int(try group.u8(entry))
            let width = rawWidth == 0 ? 256 : rawWidth
            let bits = Int(try group.u16(entry + 6))
            let id = try group.u16(entry + 12)
            if best == nil || (width, bits) > (best!.width, best!.bits) {
                best = (width, bits, id, try group.bytes(entry, 12))
            }
        }
        guard let best,
              let image = try firstResource(type: rtIcon, id: UInt32(best.id), resources: resources, reader: reader)
        else { return nil }

        var ico = Data([0, 0, 1, 0, 1, 0])
        ico.append(best.entry.prefix(8))                       // width, height, colors, reserved, planes, bits
        ico.appendLE(UInt32(image.count))
        ico.appendLE(UInt32(22))
        ico.append(image)
        return ico
    }

    private struct Resources {
        let rva: Int
        let fileOffset: Int
        let size: Int
    }

    private static func resourceSection(_ r: Reader) throws -> Resources? {
        guard r.count >= 0x40, (try? r.u16(0)) == 0x5A4D else { throw PEIconError.notPortableExecutable }
        let pe = Int(try r.u32(0x3C))
        guard (try? r.u32(pe)) == 0x0000_4550 else { throw PEIconError.notPortableExecutable }
        let coff = pe + 4
        let sections = Int(try r.u16(coff + 2))
        let optionalSize = Int(try r.u16(coff + 16))
        let optional = coff + 20
        let directories: Int
        switch try r.u16(optional) {
        case 0x10B: directories = optional + 96
        case 0x20B: directories = optional + 112
        default: throw PEIconError.notPortableExecutable
        }
        let directoryCount = Int(try r.u32(directories - 4))
        guard directoryCount > 2 else { return nil }
        let rva = Int(try r.u32(directories + 16))
        let size = Int(try r.u32(directories + 20))
        guard rva != 0, size != 0 else { return nil }

        let table = optional + optionalSize
        for index in 0..<sections {
            let header = table + index * 40
            let virtualAddress = Int(try r.u32(header + 12))
            let virtualSize = Int(try r.u32(header + 8))
            let rawSize = Int(try r.u32(header + 16))
            let rawOffset = Int(try r.u32(header + 20))
            if rva >= virtualAddress, rva < virtualAddress + max(virtualSize, rawSize) {
                return Resources(rva: rva, fileOffset: rawOffset + (rva - virtualAddress), size: size)
            }
        }
        throw PEIconError.malformed
    }

    /// Walks type → id → language and returns the first matching leaf's bytes.
    private static func firstResource(type: UInt32, id: UInt32?, resources: Resources, reader r: Reader) throws -> Data? {
        func entries(_ directory: Int) throws -> [(id: UInt32, target: UInt32)] {
            let base = resources.fileOffset + directory
            let count = Int(try r.u16(base + 12)) + Int(try r.u16(base + 14))
            guard count <= 4096 else { throw PEIconError.malformed }
            return try (0..<count).map { (try r.u32(base + 16 + $0 * 8), try r.u32(base + 20 + $0 * 8)) }
        }
        func subdirectory(_ target: UInt32) throws -> Int {
            guard target & 0x8000_0000 != 0 else { throw PEIconError.malformed }
            return Int(target & 0x7FFF_FFFF)
        }

        guard let typeEntry = try entries(0).first(where: { $0.id == type }) else { return nil }
        let ids = try entries(try subdirectory(typeEntry.target))
        guard let idEntry = id.map({ wanted in ids.first { $0.id == wanted } }) ?? ids.first else { return nil }
        guard let languageEntry = try entries(try subdirectory(idEntry.target)).first else { return nil }
        guard languageEntry.target & 0x8000_0000 == 0 else { throw PEIconError.malformed }

        let leaf = resources.fileOffset + Int(languageEntry.target)
        let dataRVA = Int(try r.u32(leaf))
        let size = Int(try r.u32(leaf + 4))
        return try r.bytes(resources.fileOffset + (dataRVA - resources.rva), size)
    }

    private struct Reader {
        let data: Data
        var count: Int { data.count }
        init(_ data: Data) { self.data = Data(data) }

        func bytes(_ offset: Int, _ length: Int) throws -> Data {
            guard offset >= 0, length >= 0, offset <= data.count, length <= data.count - offset
            else { throw PEIconError.malformed }
            return data.subdata(in: offset..<offset + length)
        }
        func u8(_ offset: Int) throws -> UInt8 { try bytes(offset, 1)[0] }
        func u16(_ offset: Int) throws -> UInt16 {
            let b = try bytes(offset, 2)
            return UInt16(b[0]) | UInt16(b[1]) << 8
        }
        func u32(_ offset: Int) throws -> UInt32 {
            let b = try bytes(offset, 4)
            return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
        }
    }
}

/// Turns an `.ico` image into ICNS data for a macOS app bundle.
public enum IconConverter {
    public static func icns(fromICO ico: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(ico as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw PEIconError.unreadableImage }

        // ICNS stores fixed sizes; scale to the nearest supported square edge.
        let edge = [16, 32, 64, 128, 256, 512].last { $0 <= max(image.width, image.height) } ?? 16
        guard let context = CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw PEIconError.unreadableImage }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))

        let output = NSMutableData()
        guard let scaled = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, UTType.icns.identifier as CFString, 1, nil)
        else { throw PEIconError.unreadableImage }
        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { throw PEIconError.unreadableImage }
        return output as Data
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
