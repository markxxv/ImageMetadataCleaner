import SwiftUI

@main
struct MetadataCleanerApp: App {
    var body: some Scene {
        Window("Metadata Cleaner", id: "main") {
            DropWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
