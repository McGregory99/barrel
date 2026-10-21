import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import BarrelCore

/// Builds a minimal PE32+ file whose `.rsrc` section holds one icon group with the given images.
enum TestPE {
    struct Image {
        var width: UInt8   // 0 means 256
        var bitCount: UInt16
        var payload: Data
    }

    static let resourceRVA: UInt32 = 0x1000
    static let resourceFileOffset = 0x200

    static func build(icons: [Image]) -> Data {
        let rsrc = resourceSection(icons: icons)
        var file = Data(count: resourceFileOffset)
        file.replace(at: 0, with: Data("MZ".utf8))
        file.put32(0x40, at: 0x3C)
        file.replace(at: 0x40, with: Data("PE\0\0".utf8))
        let coff = 0x44
        file.put16(0x8664, at: coff)            // Machine
        file.put16(1, at: coff + 2)              // NumberOfSections
        file.put16(0xF0, at: coff + 16)          // SizeOfOptionalHeader (PE32+)
        let optional = coff + 20
        file.put16(0x20B, at: optional)          // PE32+ magic
        file.put32(16, at: optional + 108)       // NumberOfRvaAndSizes
        file.put32(resourceRVA, at: optional + 112 + 2 * 8)
        file.put32(UInt32(rsrc.count), at: optional + 112 + 2 * 8 + 4)
        let section = optional + 0xF0
        file.replace(at: section, with: Data(".rsrc\0\0\0".utf8))
        file.put32(UInt32(rsrc.count), at: section + 8)     // VirtualSize
        file.put32(resourceRVA, at: section + 12)           // VirtualAddress
        file.put32(UInt32(rsrc.count), at: section + 16)    // SizeOfRawData
        file.put32(UInt32(resourceFileOffset), at: section + 20) // PointerToRawData
        return file + rsrc
    }

    /// Tree: root → {RT_ICON(3) → ids 1…n, RT_GROUP_ICON(14) → id 1} → language 0x409 → data entry.
    private static func resourceSection(icons: [Image]) -> Data {
        var group = Data()
        group.append16(0); group.append16(1); group.append16(UInt16(icons.count))
        for (index, icon) in icons.enumerated() {
            group.append(contentsOf: [icon.width, icon.width, 0, 0])
            group.append16(1); group.append16(icon.bitCount)
            group.append32(UInt32(icon.payload.count)); group.append16(UInt16(index + 1))
        }
        let blobs = icons.map(\.payload) + [group]

        // Layout: root dir (types), two id dirs, n+1 language dirs, n+1 data entries, blobs.
        let leafCount = blobs.count
        func dirSize(_ entries: Int) -> Int { 16 + 8 * entries }
        let rootOffset = 0
        let iconTypeOffset = rootOffset + dirSize(2)
        let groupTypeOffset = iconTypeOffset + dirSize(icons.count)
        let nameDirsOffset = groupTypeOffset + dirSize(1)
        let dataEntriesOffset = nameDirsOffset + leafCount * dirSize(1)
        var blobOffset = dataEntriesOffset + leafCount * 16

        var out = Data()
        func directory(_ entries: [(UInt32, UInt32)]) {
            out.append(Data(count: 12)); out.append16(0); out.append16(UInt16(entries.count))
            for (id, offset) in entries { out.append32(id); out.append32(offset) }
        }
        let subdir: UInt32 = 0x8000_0000
        directory([(3, subdir | UInt32(iconTypeOffset)), (14, subdir | UInt32(groupTypeOffset))])
        directory((0..<icons.count).map { (UInt32($0 + 1), subdir | UInt32(nameDirsOffset + $0 * dirSize(1))) })
        directory([(1, subdir | UInt32(nameDirsOffset + icons.count * dirSize(1)))])
        for leaf in 0..<leafCount { directory([(0x409, UInt32(dataEntriesOffset + leaf * 16))]) }
        for blob in blobs {
            out.append32(resourceRVA + UInt32(blobOffset)); out.append32(UInt32(blob.count))
            out.append32(0); out.append32(0)
            blobOffset += blob.count
        }
        for blob in blobs { out.append(blob) }
        return out
    }
}

extension Data {
    mutating func put16(_ value: UInt16, at offset: Int) {
        replaceSubrange(offset..<offset + 2, with: Swift.withUnsafeBytes(of: value.littleEndian) { Data($0) })
    }
    mutating func put32(_ value: UInt32, at offset: Int) {
        replaceSubrange(offset..<offset + 4, with: Swift.withUnsafeBytes(of: value.littleEndian) { Data($0) })
    }
    mutating func replace(at offset: Int, with bytes: Data) {
        replaceSubrange(offset..<offset + bytes.count, with: bytes)
    }
    mutating func append16(_ value: UInt16) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    mutating func append32(_ value: UInt32) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
}

func pngData(size: Int) throws -> Data {
    let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Suite struct PEIconTests {
    @Test func extractsTheLargestImageOfTheFirstIconGroupAsAnICOFile() throws {
        let small = Data(repeating: 0xAA, count: 40)
        let large = Data(repeating: 0xBB, count: 64)
        let pe = TestPE.build(icons: [.init(width: 16, bitCount: 32, payload: small),
                                      .init(width: 0, bitCount: 32, payload: large),
                                      .init(width: 48, bitCount: 32, payload: small)])

        let ico = try #require(try PEIcon.largestIcon(in: pe))

        #expect(ico.prefix(6) == Data([0, 0, 1, 0, 1, 0]))          // ICONDIR: type 1, one image
        #expect(ico[6] == 0)                                          // width 256
        #expect(ico.subdata(in: 14..<18) == Data([64, 0, 0, 0]))      // bytes in resource
        #expect(ico.subdata(in: 18..<22) == Data([22, 0, 0, 0]))      // image offset
        #expect(ico.suffix(from: 22) == large)
    }

    @Test func prefersMoreColorsAtTheSameSize() throws {
        let pe = TestPE.build(icons: [.init(width: 32, bitCount: 32, payload: Data([1])),
                                      .init(width: 32, bitCount: 8, payload: Data([2]))])
        let ico = try #require(try PEIcon.largestIcon(in: pe))
        #expect(ico.last == 1)
    }

    @Test func returnsNilWithoutIconResources() throws {
        #expect(try PEIcon.largestIcon(in: TestPE.build(icons: [])) == nil)
    }

    @Test(arguments: [Data(), Data("MZ".utf8), Data(repeating: 0, count: 512)])
    func rejectsDataThatIsNotAPortableExecutable(data: Data) {
        #expect(throws: PEIconError.notPortableExecutable) { try PEIcon.largestIcon(in: data) }
    }

    @Test func truncatedResourceDataIsRejected() throws {
        let pe = TestPE.build(icons: [.init(width: 0, bitCount: 32, payload: Data(repeating: 1, count: 64))])
        #expect(throws: PEIconError.malformed) { try PEIcon.largestIcon(in: pe.prefix(pe.count - 10)) }
    }

    @Test func convertsAnEmbeddedPNGIconToICNS() throws {
        let pe = TestPE.build(icons: [.init(width: 0, bitCount: 32, payload: try pngData(size: 256))])
        let ico = try #require(try PEIcon.largestIcon(in: pe))
        let icns = try IconConverter.icns(fromICO: ico)
        #expect(icns.prefix(4) == Data("icns".utf8))
    }

    @Test func conversionFailsForUnreadableImages() {
        #expect(throws: PEIconError.unreadableImage) { try IconConverter.icns(fromICO: Data([0, 0, 1, 0])) }
    }
}
