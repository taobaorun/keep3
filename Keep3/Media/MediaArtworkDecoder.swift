import CoreGraphics
import Foundation
import ImageIO

enum MediaArtworkDecoder {
  static let maximumInputBytes = MediaSession.maximumArtworkBytes
  static let maximumSourceDimension = 8_192
  static let maximumSourcePixels = 16_000_000
  static let thumbnailDimension = 512

  static func decode(_ data: Data?) -> CGImage? {
    guard let data,
      isMetadataAllowed(byteCount: data.count, frameCount: 1),
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else {
      return nil
    }

    let frameCount = CGImageSourceGetCount(source)
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(
        source,
        0,
        nil
      ) as? [CFString: Any],
      let width = number(properties[kCGImagePropertyPixelWidth]),
      let height = number(properties[kCGImagePropertyPixelHeight]),
      isMetadataAllowed(
        byteCount: data.count,
        frameCount: frameCount,
        width: width,
        height: height
      )
    else {
      return nil
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: thumbnailDimension,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      options as CFDictionary
    )
  }

  static func isMetadataAllowed(
    byteCount: Int,
    frameCount: Int,
    width: Int? = nil,
    height: Int? = nil
  ) -> Bool {
    guard byteCount > 0, byteCount <= maximumInputBytes,
      frameCount == 1
    else {
      return false
    }
    guard let width, let height else {
      return true
    }
    guard width > 0, height > 0,
      width <= maximumSourceDimension,
      height <= maximumSourceDimension
    else {
      return false
    }
    return width <= maximumSourcePixels / height
  }

  private static func number(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
  }
}
