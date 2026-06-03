import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Removes identifying metadata (EXIF, GPS, camera make/model, IPTC, maker notes…)
/// while copying the original encoded image bytes, so the picture stays visually identical.
/// Display orientation is preserved so the image is not rotated.
enum ImageMetadataCleaner {

    static func clean(from src: URL, to dst: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              let uti = CGImageSourceGetType(source) else { return false }

        let count = CGImageSourceGetCount(source)
        guard count > 0,
              let destination = CGImageDestinationCreateWithURL(dst as CFURL, uti, count, nil)
        else { return false }

        for index in 0..<count {
            let original = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]

            var removal: [CFString: Any] = [
                kCGImagePropertyExifDictionary: kCFNull,
                kCGImagePropertyExifAuxDictionary: kCFNull,
                kCGImagePropertyGPSDictionary: kCFNull,
                kCGImagePropertyIPTCDictionary: kCFNull,
                kCGImageProperty8BIMDictionary: kCFNull,
                kCGImagePropertyMakerAppleDictionary: kCFNull,
                kCGImagePropertyMakerCanonDictionary: kCFNull,
                kCGImagePropertyMakerNikonDictionary: kCFNull,
                kCGImagePropertyPNGDictionary: kCFNull
            ]

            // Drop identifying TIFF fields (Make/Model/Software) but keep orientation.
            if let tiff = original?[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let orientation = tiff[kCGImagePropertyTIFFOrientation] {
                removal[kCGImagePropertyTIFFDictionary] =
                    [kCGImagePropertyTIFFOrientation: orientation]
            } else {
                removal[kCGImagePropertyTIFFDictionary] = kCFNull
            }
            if let topOrientation = original?[kCGImagePropertyOrientation] {
                removal[kCGImagePropertyOrientation] = topOrientation
            }

            CGImageDestinationAddImageFromSource(destination, source, index, removal as CFDictionary)
        }

        return CGImageDestinationFinalize(destination)
    }
}
