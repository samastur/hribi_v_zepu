import SwiftUI

/// Loads a local image file off the main thread.
struct LocalImage: View {
    let fileURL: URL
    let contentMode: ContentMode
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Color.gray.opacity(0.15)
            }
        }
        .task(id: fileURL) {
            let path = fileURL.path
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: path)
            }.value
        }
    }
}
