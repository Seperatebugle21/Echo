import Foundation

struct PlaylistCoverGeometry {
    let imageSize: CGSize
    let side: CGFloat
    let scale: CGFloat
    init(imageSize: CGSize, side: CGFloat, zoom: CGFloat) {
        self.imageSize = imageSize; self.side = max(1, side)
        scale = max(self.side / max(1, imageSize.width), self.side / max(1, imageSize.height)) * min(4, max(1, zoom))
    }
    func clamped(_ offset: CGSize) -> CGSize {
        let x = max(0, (imageSize.width * scale - side) / 2)
        let y = max(0, (imageSize.height * scale - side) / 2)
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
    func drawingRect(offset: CGSize) -> CGRect {
        let offset = clamped(offset)
        return CGRect(x: (side - imageSize.width * scale) / 2 + offset.width,
                      y: (side - imageSize.height * scale) / 2 + offset.height,
                      width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
