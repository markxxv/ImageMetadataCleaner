import Foundation

/// Native equivalent of `xattr -c`: strips every extended attribute
/// (quarantine flags, Finder comments/info, resource forks, etc.).
enum ExtendedAttributesCleaner {

    @discardableResult
    static func clean(at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { pathPtr -> Bool in
            guard let pathPtr else { return false }

            let listSize = listxattr(pathPtr, nil, 0, 0)
            if listSize < 0 { return false }   // could not read
            if listSize == 0 { return true }   // nothing to clean

            var nameBuffer = [CChar](repeating: 0, count: listSize)
            let written = listxattr(pathPtr, &nameBuffer, listSize, 0)
            if written < 0 { return false }

            var success = true
            nameBuffer.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                var start = 0
                for i in 0..<written where buffer[i] == 0 {
                    if i > start {
                        if removexattr(pathPtr, base + start, 0) != 0 {
                            success = false
                        }
                    }
                    start = i + 1
                }
            }
            return success
        }
    }
}
