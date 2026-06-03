import Foundation
import Compression

/// Office files (DOCX/XLSX/PPTX) are ZIP packages. We rewrite the package,
/// emptying the metadata parts (`docProps/core.xml`, `docProps/custom.xml`)
/// and blanking Company/Manager in `docProps/app.xml`. Every other part is
/// copied byte-for-byte, so the document content is untouched.
enum OfficeMetadataCleaner {

    private static let emptyCore = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
    <cp:coreProperties \
    xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
    xmlns:dc="http://purl.org/dc/elements/1.1/" \
    xmlns:dcterms="http://purl.org/dc/terms/" \
    xmlns:dcmitype="http://purl.org/dc/dcmitype/" \
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"></cp:coreProperties>
    """

    private static let emptyCustom = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
    <Properties \
    xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties" \
    xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"></Properties>
    """

    static func clean(from src: URL, to dst: URL) -> Bool {
        guard let archive = ZipArchive(url: src) else { return false }

        for index in archive.entries.indices {
            switch archive.entries[index].name {
            case "docProps/core.xml":
                archive.replaceContent(at: index, with: emptyCore)
            case "docProps/custom.xml":
                archive.replaceContent(at: index, with: emptyCustom)
            case "docProps/app.xml":
                if let xml = archive.content(at: index) {
                    let cleaned = blankElement(blankElement(xml, "Company"), "Manager")
                    if cleaned != xml { archive.replaceContent(at: index, with: cleaned) }
                }
            default:
                break
            }
        }

        return archive.write(to: dst)
    }

    /// Clears the inner text of `<tag>…</tag>` if present.
    private static func blankElement(_ xml: String, _ tag: String) -> String {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>"),
              open.upperBound <= close.lowerBound else { return xml }
        return xml.replacingCharacters(in: open.upperBound..<close.lowerBound, with: "")
    }
}

// MARK: - Minimal ZIP reader / writer (no third-party dependencies)

final class ZipArchive {

    struct Entry {
        var name: String
        var method: UInt16          // 0 = stored, 8 = deflate
        var flags: UInt16
        var modTime: UInt16
        var modDate: UInt16
        var crc32: UInt32
        var compressedData: Data
        var uncompressedSize: UInt32
        var versionMadeBy: UInt16
        var versionNeeded: UInt16
        var externalAttributes: UInt32
    }

    var entries: [Entry]

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let bytes = [UInt8](data)

        guard let eocd = ZipArchive.lastIndex(of: [0x50, 0x4b, 0x05, 0x06], in: bytes) else { return nil }
        let entryCount = Int(ZipArchive.u16(bytes, eocd + 10))
        var p = Int(ZipArchive.u32(bytes, eocd + 16))

        var parsed: [Entry] = []
        parsed.reserveCapacity(entryCount)

        for _ in 0..<entryCount {
            guard p + 46 <= bytes.count, ZipArchive.u32(bytes, p) == 0x02014b50 else { return nil }

            let versionMadeBy = ZipArchive.u16(bytes, p + 4)
            let versionNeeded = ZipArchive.u16(bytes, p + 6)
            let flags = ZipArchive.u16(bytes, p + 8)
            let method = ZipArchive.u16(bytes, p + 10)
            let modTime = ZipArchive.u16(bytes, p + 12)
            let modDate = ZipArchive.u16(bytes, p + 14)
            let crc = ZipArchive.u32(bytes, p + 16)
            let compSize = Int(ZipArchive.u32(bytes, p + 20))
            let uncompSize = ZipArchive.u32(bytes, p + 24)
            let nameLen = Int(ZipArchive.u16(bytes, p + 28))
            let extraLen = Int(ZipArchive.u16(bytes, p + 30))
            let commentLen = Int(ZipArchive.u16(bytes, p + 32))
            let externalAttrs = ZipArchive.u32(bytes, p + 38)
            let localOffset = Int(ZipArchive.u32(bytes, p + 42))

            guard p + 46 + nameLen <= bytes.count else { return nil }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)

            guard localOffset + 30 <= bytes.count,
                  ZipArchive.u32(bytes, localOffset) == 0x04034b50 else { return nil }
            let localNameLen = Int(ZipArchive.u16(bytes, localOffset + 26))
            let localExtraLen = Int(ZipArchive.u16(bytes, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLen + localExtraLen
            guard dataStart + compSize <= bytes.count else { return nil }
            let compData = Data(bytes[dataStart..<(dataStart + compSize)])

            parsed.append(Entry(
                name: name,
                method: method,
                flags: flags & ~0x0008,          // drop the data-descriptor bit; we write sizes inline
                modTime: modTime,
                modDate: modDate,
                crc32: crc,
                compressedData: compData,
                uncompressedSize: uncompSize,
                versionMadeBy: versionMadeBy,
                versionNeeded: versionNeeded,
                externalAttributes: externalAttrs
            ))

            p += 46 + nameLen + extraLen + commentLen
        }

        self.entries = parsed
    }

    func content(at index: Int) -> String? {
        let entry = entries[index]
        let raw: Data?
        switch entry.method {
        case 0:  raw = entry.compressedData
        case 8:  raw = RawDeflate.inflate(entry.compressedData, expectedSize: Int(entry.uncompressedSize))
        default: raw = nil
        }
        guard let raw else { return nil }
        return String(data: raw, encoding: .utf8)
    }

    func replaceContent(at index: Int, with string: String) {
        let data = Data(string.utf8)
        var entry = entries[index]
        entry.uncompressedSize = UInt32(data.count)
        entry.crc32 = CRC32.checksum(data)

        if let deflated = RawDeflate.deflate(data), deflated.count < data.count {
            entry.method = 8
            entry.compressedData = deflated
        } else {
            entry.method = 0
            entry.compressedData = data
        }
        entries[index] = entry
    }

    func write(to url: URL) -> Bool {
        var out = Data()
        var offsets: [Int] = []
        offsets.reserveCapacity(entries.count)

        // Local file headers + data
        for entry in entries {
            offsets.append(out.count)
            let nameBytes = Array(entry.name.utf8)
            ZipArchive.appendU32(&out, 0x04034b50)
            ZipArchive.appendU16(&out, entry.versionNeeded)
            ZipArchive.appendU16(&out, entry.flags)
            ZipArchive.appendU16(&out, entry.method)
            ZipArchive.appendU16(&out, entry.modTime)
            ZipArchive.appendU16(&out, entry.modDate)
            ZipArchive.appendU32(&out, entry.crc32)
            ZipArchive.appendU32(&out, UInt32(entry.compressedData.count))
            ZipArchive.appendU32(&out, entry.uncompressedSize)
            ZipArchive.appendU16(&out, UInt16(nameBytes.count))
            ZipArchive.appendU16(&out, 0)
            out.append(contentsOf: nameBytes)
            out.append(entry.compressedData)
        }

        // Central directory
        let cdStart = out.count
        for (i, entry) in entries.enumerated() {
            let nameBytes = Array(entry.name.utf8)
            ZipArchive.appendU32(&out, 0x02014b50)
            ZipArchive.appendU16(&out, entry.versionMadeBy)
            ZipArchive.appendU16(&out, entry.versionNeeded)
            ZipArchive.appendU16(&out, entry.flags)
            ZipArchive.appendU16(&out, entry.method)
            ZipArchive.appendU16(&out, entry.modTime)
            ZipArchive.appendU16(&out, entry.modDate)
            ZipArchive.appendU32(&out, entry.crc32)
            ZipArchive.appendU32(&out, UInt32(entry.compressedData.count))
            ZipArchive.appendU32(&out, entry.uncompressedSize)
            ZipArchive.appendU16(&out, UInt16(nameBytes.count))
            ZipArchive.appendU16(&out, 0)   // extra
            ZipArchive.appendU16(&out, 0)   // comment
            ZipArchive.appendU16(&out, 0)   // disk number
            ZipArchive.appendU16(&out, 0)   // internal attrs
            ZipArchive.appendU32(&out, entry.externalAttributes)
            ZipArchive.appendU32(&out, UInt32(offsets[i]))
            out.append(contentsOf: nameBytes)
        }
        let cdSize = out.count - cdStart

        // End of central directory
        ZipArchive.appendU32(&out, 0x06054b50)
        ZipArchive.appendU16(&out, 0)
        ZipArchive.appendU16(&out, 0)
        ZipArchive.appendU16(&out, UInt16(entries.count))
        ZipArchive.appendU16(&out, UInt16(entries.count))
        ZipArchive.appendU32(&out, UInt32(cdSize))
        ZipArchive.appendU32(&out, UInt32(cdStart))
        ZipArchive.appendU16(&out, 0)

        return (try? out.write(to: url)) != nil
    }

    // MARK: Little-endian byte helpers

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
    private static func appendU16(_ d: inout Data, _ v: UInt16) {
        d.append(UInt8(v & 0xff)); d.append(UInt8((v >> 8) & 0xff))
    }
    private static func appendU32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8(v & 0xff)); d.append(UInt8((v >> 8) & 0xff))
        d.append(UInt8((v >> 16) & 0xff)); d.append(UInt8((v >> 24) & 0xff))
    }
    private static func lastIndex(of sig: [UInt8], in bytes: [UInt8]) -> Int? {
        guard bytes.count >= sig.count else { return nil }
        var i = bytes.count - sig.count
        while i >= 0 {
            if Array(bytes[i..<(i + sig.count)]) == sig { return i }
            i -= 1
        }
        return nil
    }
}

// MARK: - CRC32 (IEEE) for rewritten entries

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var c = UInt32(index)
            for _ in 0..<8 {
                c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Raw DEFLATE (RFC 1951) via Apple's Compression framework

enum RawDeflate {
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + data.count / 2 + 128
        var dst = Data(count: capacity)
        let written = dst.withUnsafeMutableBytes { dstRaw in
            data.withUnsafeBytes { srcRaw in
                compression_encode_buffer(
                    dstRaw.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    srcRaw.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        dst.removeSubrange(written..<dst.count)
        return dst
    }

    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var dst = Data(count: expectedSize)
        let written = dst.withUnsafeMutableBytes { dstRaw in
            data.withUnsafeBytes { srcRaw in
                compression_decode_buffer(
                    dstRaw.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    srcRaw.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        if written != dst.count { dst.removeSubrange(written..<dst.count) }
        return dst
    }
}
