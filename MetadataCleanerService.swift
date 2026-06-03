import Foundation

/// Orchestrates cleaning: picks the right strategy for the file type,
/// writes a `.cleaned` copy next to the original, and always strips
/// macOS extended attributes. The original file is never modified.
struct MetadataCleanerService {

    func clean(url: URL) async -> CleaningResult {
        // Allow access to a security-scoped URL handed over via drag & drop.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return CleaningResult(originalURL: url,
                                  cleanedURL: nil,
                                  status: .failure("File could not be found."))
        }

        let category = FileTypeDetector.category(for: url)
        let dst = FileCopyHelper.makeCleanedURL(for: url)

        // Run the type-specific deep cleaner, which writes directly to `dst`.
        let produced: Bool
        switch category {
        case .image:  produced = ImageMetadataCleaner.clean(from: url, to: dst)
        case .pdf:    produced = PDFMetadataCleaner.clean(from: url, to: dst)
        case .office: produced = OfficeMetadataCleaner.clean(from: url, to: dst)
        case .media:  produced = await MediaMetadataCleaner.clean(from: url, to: dst)
        case .unknown: produced = false
        }

        if produced {
            // Deep clean succeeded — also strip filesystem-level attributes.
            ExtendedAttributesCleaner.clean(at: dst)
            return CleaningResult(originalURL: url, cleanedURL: dst, status: .success)
        }

        // Fallback: copy the file untouched and strip macOS attributes only.
        guard FileCopyHelper.copyItem(from: url, to: dst) else {
            return CleaningResult(originalURL: url,
                                  cleanedURL: nil,
                                  status: .failure("Could not clean this file type."))
        }
        ExtendedAttributesCleaner.clean(at: dst)

        switch category {
        case .unknown:
            // Nothing more is expected for unknown types — this is a success.
            return CleaningResult(originalURL: url, cleanedURL: dst, status: .success)
        default:
            // A known type whose deep cleaning failed — partial result.
            return CleaningResult(
                originalURL: url,
                cleanedURL: dst,
                status: .warning("Cleaned macOS attributes; embedded metadata couldn't be fully removed."))
        }
    }
}
