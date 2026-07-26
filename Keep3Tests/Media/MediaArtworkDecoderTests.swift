import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
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

  func testCachesDecodedArtworkByPayload() {
    let png = Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    let first = MediaArtworkDecoder.decode(png)
    let second = MediaArtworkDecoder.decode(Data(png))

    XCTAssertTrue(first === second)
  }

  func testSolidArtworkProducesDistinctReadableAccents() throws {
    let red = try pngData(
      width: 8,
      height: 8,
      pixels: Array(
        repeating: Pixel(red: 220, green: 28, blue: 38),
        count: 64
      )
    )
    let blue = try pngData(
      width: 8,
      height: 8,
      pixels: Array(
        repeating: Pixel(red: 28, green: 82, blue: 220),
        count: 64
      )
    )

    let redAccent = MediaArtworkDecoder.resolve(red).accent
    let blueAccent = MediaArtworkDecoder.resolve(blue).accent

    XCTAssertNotEqual(redAccent, blueAccent)
    XCTAssertGreaterThan(redAccent.red, redAccent.blue)
    XCTAssertGreaterThan(blueAccent.blue, blueAccent.red)
    XCTAssertGreaterThanOrEqual(redAccent.contrastAgainstBlack, 3)
    XCTAssertGreaterThanOrEqual(blueAccent.contrastAgainstBlack, 3)
  }

  func testDominantRegionWinsOverCornerColor() throws {
    var pixels = Array(
      repeating: Pixel(red: 24, green: 72, blue: 224),
      count: 64
    )
    for row in 0..<8 {
      for column in 0..<2 {
        pixels[(row * 8) + column] = Pixel(
          red: 224,
          green: 36,
          blue: 28
        )
      }
    }
    let artwork = try pngData(width: 8, height: 8, pixels: pixels)

    let accent = MediaArtworkDecoder.resolve(artwork).accent

    XCTAssertGreaterThan(accent.blue, accent.red)
    XCTAssertGreaterThanOrEqual(accent.contrastAgainstBlack, 3)
  }

  func testUnusableArtworkUsesFallbackAndDarkColorIsNormalized() throws {
    let transparent = try pngData(
      width: 8,
      height: 8,
      pixels: Array(
        repeating: Pixel(red: 255, green: 0, blue: 0, alpha: 0),
        count: 64
      )
    )
    let grayscale = try pngData(
      width: 8,
      height: 8,
      pixels: Array(
        repeating: Pixel(red: 96, green: 96, blue: 96),
        count: 64
      )
    )
    let darkBlue = try pngData(
      width: 8,
      height: 8,
      pixels: Array(
        repeating: Pixel(red: 0, green: 0, blue: 24),
        count: 64
      )
    )

    XCTAssertEqual(MediaArtworkDecoder.resolve(nil).accent, .fallback)
    XCTAssertEqual(
      MediaArtworkDecoder.resolve(Data("not-an-image".utf8)).accent,
      .fallback
    )
    XCTAssertEqual(
      MediaArtworkDecoder.resolve(transparent).accent,
      .fallback
    )
    XCTAssertEqual(
      MediaArtworkDecoder.resolve(grayscale).accent,
      .fallback
    )
    XCTAssertGreaterThanOrEqual(
      MediaArtworkAccent.fallback.contrastAgainstBlack,
      3
    )

    let normalizedDarkBlue = MediaArtworkDecoder.resolve(darkBlue).accent
    XCTAssertNotEqual(normalizedDarkBlue, .fallback)
    XCTAssertGreaterThan(normalizedDarkBlue.blue, normalizedDarkBlue.red)
    XCTAssertGreaterThanOrEqual(
      normalizedDarkBlue.contrastAgainstBlack,
      3
    )
  }

  func testResolverCachesImageAndAccentWithoutGlobalCacheInterference()
    throws
  {
    let resolver = MediaArtworkResolver()
    let firstArtwork = try pngData(
      width: 8,
      height: 8,
      pixels: Array(
        repeating: Pixel(red: 220, green: 28, blue: 38),
        count: 64
      )
    )
    let secondArtwork = try pngData(
      width: 8,
      height: 8,
      pixels: Array(
        repeating: Pixel(red: 28, green: 82, blue: 220),
        count: 64
      )
    )

    let first = resolver.resolve(firstArtwork)
    let repeated = resolver.resolve(Data(firstArtwork))
    let changed = resolver.resolve(secondArtwork)

    XCTAssertTrue(first.image === repeated.image)
    XCTAssertEqual(first.accent, repeated.accent)
    XCTAssertNotEqual(first.accent, changed.accent)
    XCTAssertEqual(resolver.accentExtractionCount, 2)
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

  private struct Pixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    init(
      red: UInt8,
      green: UInt8,
      blue: UInt8,
      alpha: UInt8 = 255
    ) {
      self.red = red
      self.green = green
      self.blue = blue
      self.alpha = alpha
    }
  }

  private func pngData(
    width: Int,
    height: Int,
    pixels: [Pixel]
  ) throws -> Data {
    XCTAssertEqual(pixels.count, width * height)
    var bytes = pixels.flatMap {
      let alpha = UInt16($0.alpha)
      return [
        UInt8((UInt16($0.red) * alpha) / 255),
        UInt8((UInt16($0.green) * alpha) / 255),
        UInt8((UInt16($0.blue) * alpha) / 255),
        $0.alpha,
      ]
    }
    let image = try XCTUnwrap(
      bytes.withUnsafeMutableBytes { buffer -> CGImage? in
        guard
          let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo:
              CGImageAlphaInfo.premultipliedLast.rawValue
              | CGBitmapInfo.byteOrder32Big.rawValue
          )
        else {
          return nil
        }
        return context.makeImage()
      }
    )
    let data = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    )
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }
}
