import Foundation

enum CleaningStatus {
    case success
    case warning(String)
    case failure(String)
}

struct CleaningResult {
    let originalURL: URL
    let cleanedURL: URL?
    let status: CleaningStatus
}
