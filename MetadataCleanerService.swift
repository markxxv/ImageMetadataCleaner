import Foundation

/// Orchestrates cleaning: picks the right strategy for the file type,
/// cleans into a temporary file, then overwrites the ORIGINAL file in place,
/// and always strips macOS extended attributes.
///
/// WARNING: this version overwrites the original file. There is no undo.
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

        // Temp output next to the original (same volume → atomic replace works).
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(url.pathExtension)")

        // Run the type-specific deep cleaner, which writes to the temp file.
        let produced: Bool
        switch category {
        case .image:  produced = ImageMetadataCleaner.clean(from: url, to: tmp)
        case .pdf:    produced = PDFMetadataCleaner.clean(from: url, to: tmp)
        case .office: produced = OfficeMetadataCleaner.clean(from: url, to: tmp)
        case .media:  produced = await MediaMetadataCleaner.clean(from: url, to: tmp)
        case .unknown: produced = false
        }

        if produced {
            // Replace the original with the cleaned temp file.
            if replaceOriginal(url, with: tmp) {
                ExtendedAttributesCleaner.clean(at: url)
                return CleaningResult(originalURL: url, cleanedURL: url, status: .success)
            }
            try? FileManager.default.removeItem(at: tmp)
            return CleaningResult(originalURL: url,
                                  cleanedURL: nil,
                                  status: .failure("Could not overwrite the original file."))
        }

        // No deep clean available — strip macOS attributes on the original in place.
        try? FileManager.default.removeItem(at: tmp)
        ExtendedAttributesCleaner.clean(at: url)

        switch category {
        case .unknown:
            return CleaningResult(originalURL: url, cleanedURL: url, status: .success)
        default:
            return CleaningResult(
                originalURL: url,
                cleanedURL: url,
                status: .warning("Cleaned macOS attributes; embedded metadata couldn't be fully removed."))
        }
    }

    /// Atomically swaps the original file for the cleaned temp file,
    /// preserving the original's name and location.
    private func replaceOriginal(_ original: URL, with tmp: URL) -> Bool {
        do {
            _ = try FileManager.default.replaceItemAt(original, withItemAt: tmp)
            return true
        } catch {
            return false
        }
    }
}
