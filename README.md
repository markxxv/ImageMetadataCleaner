# Metadata Cleaner

A tiny native macOS app utility to clean file metadata with a simple drag and drop.
.

## Build

You need macOS 15.7+ and the Xcode command line tools:

```bash
xcode-select --install   # once, if you don't have them
```

Then:

```bash
cd MetadataCleaner
chmod +x build.sh
./build.sh
```

This produces `build/Metadata Cleaner.app`.

## Install & run

1. Drag `build/Metadata Cleaner.app` into `/Applications`.
2. First launch only: right-click the app → **Open** → **Open**
   (it's ad-hoc signed, so this clears Gatekeeper once).
3. After that, open it normally from Launchpad or Applications.


## What gets cleaned

- **Images** (JPG, PNG, HEIC, TIFF, WebP): EXIF, GPS, camera/lens, dates,
  software, thumbnails, author/copyright. Orientation is preserved.
- **PDF**: title, author, subject, keywords, creator, producer, dates.
- **Office** (DOCX, XLSX, PPTX): author, last-modified-by, company, dates,
  custom properties.
- **Audio/Video** (MP3, M4A, MP4, MOV, WAV, AIFF): embedded tags/metadata.
- **Every file**: macOS extended attributes (quarantine, Finder info,
  resource forks) — the equivalent of `xattr -c`.
- **Unknown types**: a safe copy with macOS attributes stripped.

## Notes

- No third-party dependencies — only Apple SwiftUI & ImageIO,
  PDFKit, AVFoundation, Compression.
- If you ever hit linker errors on an unusual toolchain, add explicit flags to
  `build.sh`, e.g. `-framework SwiftUI -framework PDFKit -framework AVFoundation`.
