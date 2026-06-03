import Foundation
import UniformTypeIdentifiers

enum FileCategory {
    case image
    case pdf
    case office
    case media
    case unknown
}

enum FileTypeDetector {

    private static let officeExtensions: Set<String> = ["docx", "xlsx", "pptx"]
    private static let mediaExtensions: Set<String> =
        ["mp3", "m4a", "mp4", "mov", "wav", "aiff", "aif", "aifc"]

    static func category(for url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()

        if officeExtensions.contains(ext) { return .office }
        if mediaExtensions.contains(ext) { return .media }
        if ext == "pdf" { return .pdf }

        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: ext)

        if let type {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .audiovisualContent) || type.conforms(to: .audio) { return .media }
        }
        return .unknown
    }
}
