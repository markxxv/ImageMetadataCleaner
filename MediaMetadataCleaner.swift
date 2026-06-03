import Foundation
import AVFoundation

/// Removes media metadata. Container formats (MP4/MOV/M4A/WAV/AIFF) are
/// re-muxed with an empty metadata set via a passthrough export, so the
/// audio/video samples are copied without re-encoding. MP3 is handled by
/// stripping ID3 tags directly.
enum MediaMetadataCleaner {

    static func clean(from src: URL, to dst: URL) async -> Bool {
        if src.pathExtension.lowercased() == "mp3" {
            return stripID3(from: src, to: dst)
        }

        guard let fileType = outputType(for: dst) else { return false }

        let asset = AVURLAsset(url: src)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetPassthrough),
              session.supportedFileTypes.contains(fileType) else { return false }

        session.metadata = []

        do {
            try await session.export(to: dst, as: fileType)
            return true
        } catch {
            return false
        }
    }

    private static func outputType(for url: URL) -> AVFileType? {
        switch url.pathExtension.lowercased() {
        case "mp4":          return .mp4
        case "mov":          return .mov
        case "m4a":          return .m4a
        case "wav":          return .wav
        case "aiff", "aif":  return .aiff
        case "aifc":         return .aifc
        default:             return nil
        }
    }

    /// Removes a leading ID3v2 tag and a trailing ID3v1 tag; audio frames stay intact.
    private static func stripID3(from src: URL, to dst: URL) -> Bool {
        guard let data = try? Data(contentsOf: src) else { return false }
        let bytes = [UInt8](data)

        var start = 0
        if bytes.count > 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {
            // ID3v2 size is a 28-bit synchsafe integer in bytes 6...9.
            let size = (Int(bytes[6] & 0x7f) << 21)
                     | (Int(bytes[7] & 0x7f) << 14)
                     | (Int(bytes[8] & 0x7f) << 7)
                     |  Int(bytes[9] & 0x7f)
            let footer = (bytes[5] & 0x10) != 0 ? 10 : 0
            start = min(10 + size + footer, bytes.count)
        }

        var end = bytes.count
        if end - start >= 128,
           bytes[end - 128] == 0x54, bytes[end - 127] == 0x41, bytes[end - 126] == 0x47 {
            end -= 128   // "TAG" → ID3v1 footer
        }

        guard start < end else { return false }
        let audio = data.subdata(in: start..<end)
        return (try? audio.write(to: dst)) != nil
    }
}
