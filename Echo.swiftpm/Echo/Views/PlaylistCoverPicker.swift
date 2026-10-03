import SwiftUI
import PhotosUI
import ImageIO

enum PlaylistCovers {
    static let graphics = (1...24).map { String(format: "graphic-%02d", $0) }
    static let illustrations = (1...24).map { String(format: "illustration-%02d", $0) }
    static func url(_ id: String) -> URL? {
        guard (graphics + illustrations).contains(id) else { return nil }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle.url(forResource: id, withExtension: "jpg", subdirectory: "PlaylistCovers") ?? bundle.url(forResource: id, withExtension: "jpg")
    }
}

actor CoverThumbnailCache {
    static let shared = CoverThumbnailCache()
    private var images: [String: UIImage] = [:]
    func image(data: Data?, builtin: String?, pixels: Int) -> UIImage? {
        let key = "\(builtin ?? "custom")|\(data?.hashValue ?? 0)|\(pixels)"
        if let image = images[key] { return image }
        let source: CGImageSource?
        if let builtin, let url = PlaylistCovers.url(builtin) { source = CGImageSourceCreateWithURL(url as CFURL, nil) }
        else if builtin == nil, let data { source = CGImageSourceCreateWithData(data as CFData, nil) }
        else { return nil }
        guard let source, let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        if images.count >= 96 { images.removeAll(keepingCapacity: true) }
        images[key] = image; return image
    }
}

struct PlaylistCoverArtwork: View {
    var data: Data?
    var builtin: String?
    var pixels = 512
    var symbol = "music.note.list"
    @State private var image: UIImage?
    private struct Source: Hashable { var data: Data?; var builtin: String?; var pixels: Int }
    var body: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary) }
        }
        .clipped()
        .task(id: Source(data: data, builtin: builtin, pixels: pixels)) {
            let loaded = await CoverThumbnailCache.shared.image(data: data, builtin: builtin, pixels: pixels)
            if !Task.isCancelled { image = loaded }
        }
        .accessibilityHidden(true)
    }
}

struct PlaylistCoverSelector: View {
    @Binding var imageData: Data?
    @Binding var builtinCoverID: String?
    @State private var gallery = false
    var body: some View {
        Button { gallery = true } label: {
            HStack(spacing: 16) {
                PlaylistCoverArtwork(data: imageData, builtin: builtinCoverID).frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 18))
                Label("select_cover_image_accessibility", systemImage: "photo.on.rectangle.angled")
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain)
        .accessibilityLabel("select_cover_image_accessibility")
        .sheet(isPresented: $gallery) { PlaylistCoverGallery(imageData: $imageData, builtinCoverID: $builtinCoverID) }
    }
}

private struct CropSource: Identifiable { let id = UUID(); let image: UIImage }
struct PlaylistCoverGallery: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var imageData: Data?
    @Binding var builtinCoverID: String?
    @State private var photo: PhotosPickerItem?
    @State private var crop: CropSource?
    @State private var loading = false
    @State private var failed = false
    @State private var loadTask: Task<Void, Never>?
    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 150), spacing: 12)]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PhotosPicker(selection: $photo, matching: .images) { Label("cover_own_photo", systemImage: "photo.badge.plus").frame(maxWidth: .infinity).padding() }
                        .buttonStyle(.bordered)
                    if loading { ProgressView("cover_loading").frame(maxWidth: .infinity) }
                    section("cover_graphics", ids: PlaylistCovers.graphics)
                    section("cover_illustrations", ids: PlaylistCovers.illustrations)
                    Button("cover_remove", role: .destructive) { imageData = nil; builtinCoverID = nil; dismiss() }
                }.padding()
            }.echoBackground().navigationTitle("cover_gallery_title").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action_cancel") { dismiss() } } }
                .onChange(of: photo) {
                    loadTask?.cancel(); loading = true
                    let selected = photo
                    loadTask = Task {
                        guard let data = try? await selected?.loadTransferable(type: Data.self) else {
                            if !Task.isCancelled { loading = false; failed = true }; return
                        }
                        guard !Task.isCancelled else { return }
                        let image = await CoverThumbnailCache.shared.image(data: data, builtin: nil, pixels: 4096)
                        guard !Task.isCancelled else { return }
                        loading = false
                        if let image { crop = CropSource(image: image) } else { failed = true }
                    }
                }
                .sheet(item: $crop) { source in
                    SquareCoverCropView(image: source.image) { result in
                        imageData = result; builtinCoverID = nil; crop = nil; dismiss()
                    }
                }
                .alert("cover_load_failed", isPresented: $failed) { Button("action_cancel", role: .cancel) {} }
                .onDisappear { loadTask?.cancel() }
        }
    }
    private func section(_ key: LocalizedStringKey, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(key).font(.title3.bold())
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    Button { builtinCoverID = id; imageData = nil; dismiss() } label: {
                        PlaylistCoverArtwork(data: nil, builtin: id, pixels: 256).aspectRatio(1, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 18))
                            .overlay(alignment: .bottomTrailing) {
                                if builtinCoverID == id { Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor).padding(8) }
                            }
                    }.buttonStyle(.plain).accessibilityLabel(Text("cover_number \(index + 1)"))
                        .accessibilityAddTraits(builtinCoverID == id ? [.isSelected] : [])
                }
            }
        }
    }
}

private struct SquareCoverCropView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let save: (Data) -> Void
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    @State private var saving = false
    @State private var cropTask: Task<Void, Never>?
    @State private var error = false
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let side = max(1, min(geometry.size.width - 32, geometry.size.height - 120))
                let scale = max(side / image.size.width, side / image.size.height) * min(4, max(1, zoom * pinch))
                let displacement = bounded(CGSize(width: offset.width + drag.width, height: offset.height + drag.height), side: side, scale: scale)
                VStack(spacing: 20) {
                    Spacer()
                    Image(uiImage: image).resizable().frame(width: image.size.width * scale, height: image.size.height * scale)
                        .offset(displacement).frame(width: side, height: side).clipped()
                        .overlay(Rectangle().stroke(.white.opacity(0.9), lineWidth: 2))
                        .contentShape(Rectangle())
                        .accessibilityLabel("cover_crop_title")
                        .accessibilityAction(named: Text("cover_move_left")) { offset = bounded(CGSize(width: offset.width - side / 10, height: offset.height), side: side, scale: scale) }
                        .accessibilityAction(named: Text("cover_move_right")) { offset = bounded(CGSize(width: offset.width + side / 10, height: offset.height), side: side, scale: scale) }
                        .accessibilityAction(named: Text("cover_move_up")) { offset = bounded(CGSize(width: offset.width, height: offset.height - side / 10), side: side, scale: scale) }
                        .accessibilityAction(named: Text("cover_move_down")) { offset = bounded(CGSize(width: offset.width, height: offset.height + side / 10), side: side, scale: scale) }
                        .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }.onEnded { value in offset = bounded(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height), side: side, scale: scale) })
                        .simultaneousGesture(MagnifyGesture().updating($pinch) { value, state, _ in state = value.magnification }.onEnded { value in zoom = min(4, max(1, zoom * value.magnification)); offset = bounded(offset, side: side, scale: max(side / image.size.width, side / image.size.height) * zoom) })
                    Text("cover_crop_hint").font(.footnote).foregroundStyle(.secondary)
                    Slider(value: $zoom, in: 1...4).accessibilityLabel("cover_zoom").padding(.horizontal, 24)
                    Spacer()
                }.frame(maxWidth: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("action_cancel") { dismiss() } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("cover_use_photo") {
                                saving = true
                                let rect = PlaylistCoverGeometry(imageSize: image.size, side: side, zoom: zoom).drawingRect(offset: offset)
                                cropTask = Task {
                                    let output = await Task.detached(priority: .userInitiated) {
                                        let format = UIGraphicsImageRendererFormat(); format.scale = 1
                                        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { context in
                                            context.cgContext.scaleBy(x: 1024 / side, y: 1024 / side); image.draw(in: rect)
                                        }.jpegData(compressionQuality: 0.88)
                                    }.value
                                    guard !Task.isCancelled else { return }
                                    saving = false
                                    if let output { save(output) } else { error = true }
                                }
                            }.disabled(saving)
                        }
                    }
            }.echoBackground().navigationTitle("cover_crop_title").navigationBarTitleDisplayMode(.inline)
                .alert("cover_load_failed", isPresented: $error) { Button("action_cancel", role: .cancel) {} }
                .onDisappear { cropTask?.cancel(); cropTask = nil }
        }
    }
    private func bounded(_ offset: CGSize, side: CGFloat, scale: CGFloat) -> CGSize {
        let base = max(side / image.size.width, side / image.size.height)
        return PlaylistCoverGeometry(imageSize: image.size, side: side, zoom: scale / base).clamped(offset)
    }
}
