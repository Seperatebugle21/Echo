import XCTest
import UIKit

@MainActor
final class EchoArtworkTests: XCTestCase {
    func testArtworkIsDownsampledAndSharedAcrossConcurrentConsumers() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200), format: {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; return format
        }())
        let data = renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        }
        let store = ArtworkThumbnailStore()
        async let a = store.thumbnail(data)
        async let b = store.thumbnail(data)
        let (first, second) = await (a, b)
        let image = try XCTUnwrap(first)
        XCTAssertTrue(image === second)
        XCTAssertEqual(image.cgImage?.width, 600)
        XCTAssertEqual(image.cgImage?.height, 450)
        let cached = await store.thumbnail(data)
        XCTAssertTrue(image === cached)
    }

    func testInvalidAndMissingArtworkUsePlaceholderWithoutCachingWrongImage() async {
        let store = ArtworkThumbnailStore()
        let missing = await store.thumbnail(nil)
        let invalid = await store.thumbnail(Data("invalid image".utf8))
        XCTAssertNil(missing)
        XCTAssertNil(invalid)
    }
}
