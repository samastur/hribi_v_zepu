import SwiftUI

struct PagerItem: Identifiable {
    let id: Int
    let fileURL: URL
    let caption: String?
}

struct PhotoPagerView: View {
    let items: [PagerItem]
    let startIndex: Int
    let onClose: () -> Void
    @State private var index: Int?

    init(items: [PagerItem], startIndex: Int, onClose: @escaping () -> Void) {
        self.items = items
        self.startIndex = startIndex
        self.onClose = onClose
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(items) { item in
                        ZoomableImage(fileURL: item.fileURL)
                            .containerRelativeFrame(.horizontal)
                            .frame(maxHeight: .infinity)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $index)
            VStack {
                HStack {
                    Text("\((index ?? 0) + 1) / \(items.count)")
                        .foregroundStyle(.white)
                        .padding(.leading)
                    Spacer()
                    Button { onClose() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                    .padding(.trailing)
                }
                Spacer()
            }
            VStack {
                Spacer()
                if let caption = items.first(where: { $0.id == (index ?? 0) })?.caption, !caption.isEmpty {
                    Text(caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.55))
                        .padding(.bottom, 24)
                }
            }
        }
    }
}

/// Pinch-to-zoom that snaps back on release (v1 behaviour).
struct ZoomableImage: View {
    let fileURL: URL
    @State private var scale: CGFloat = 1
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale = max(1, $0) }
                            .onEnded { _ in withAnimation(.spring) { scale = 1 } }
                    )
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.gray)
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
