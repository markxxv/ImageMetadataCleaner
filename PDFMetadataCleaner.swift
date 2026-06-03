import Foundation
import PDFKit

/// Clears PDF document information (title, author, subject, keywords,
/// creator, producer, creation/modification dates) and rewrites the file.
enum PDFMetadataCleaner {

    static func clean(from src: URL, to dst: URL) -> Bool {
        guard let document = PDFDocument(url: src) else { return false }
        document.documentAttributes = [:]
        return document.write(to: dst)
    }
}
