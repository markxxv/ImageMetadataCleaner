import Foundation

/// Decides where the cleaned copy goes and never touches the original.
enum FileCopyHelper {

    /// `name.cleaned.ext`, falling back to `name.cleaned-2.ext`, `-3` … if taken.
    /// Saves next to the original when writable, otherwise in Downloads.
    static func makeCleanedURL(for original: URL) -> URL {
        let folder = original.deletingLastPathComponent()
        let targetFolder = isWritable(folder) ? folder : downloadsFolder()
        return uniqueURL(in: targetFolder,
                         baseName: original.deletingPathExtension().lastPathComponent,
                         ext: original.pathExtension)
    }

    @discardableResult
    static func copyItem(from src: URL, to dst: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            return true
        } catch {
            return false
        }
    }

    private static func uniqueURL(in folder: URL, baseName: String, ext: String) -> URL {
        let fm = FileManager.default

        func fileName(_ suffix: String) -> String {
            ext.isEmpty
                ? "\(baseName).cleaned\(suffix)"
                : "\(baseName).cleaned\(suffix).\(ext)"
        }

        var candidate = folder.appendingPathComponent(fileName(""))
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(fileName("-\(counter)"))
            counter += 1
        }
        return candidate
    }

    private static func isWritable(_ folder: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: folder.path)
    }

    private static func downloadsFolder() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}
