import Foundation
import XCTest

@testable import Keep3

final class MediaArtworkDecoderTests: XCTestCase {
  func testDecodesOneBoundedStaticImage() {
    let png = Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )

    XCTAssertNotNil(MediaArtworkDecoder.decode(png))
  }

  func testRejectsMalformedAnimatedAndOversizedInputs() {
    XCTAssertNil(MediaArtworkDecoder.decode(Data("not-an-image".utf8)))
    XCTAssertFalse(
      MediaArtworkDecoder.isMetadataAllowed(
        byteCount: 1_024,
        frameCount: 2,
        width: 200,
        height: 200
      )
    )
    XCTAssertFalse(
      MediaArtworkDecoder.isMetadataAllowed(
        byteCount: 1_024,
        frameCount: 1,
        width: 8_000,
        height: 8_000
      )
    )
    XCTAssertFalse(
      MediaArtworkDecoder.isMetadataAllowed(
        byteCount: MediaArtworkDecoder.maximumInputBytes + 1,
        frameCount: 1
      )
    )
  }
}
