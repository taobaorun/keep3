import CoreGraphics
import Foundation
import ImageIO

enum MediaArtworkDecoder {
  static let maximumInputBytes = MediaSession.maximumArtworkBytes
  static let maximumSourceDimension = 8_192
  static let maximumSourcePixels = 16_000_000
  static let thumbnailDimension = 512
  private static let cache = MediaArtworkCache()

  static func decode(_ data: Data?) -> CGImage? {
    guard let data else {
      return nil
    }
    if let cached = cache.image(for: data) {
      return cached
    }
    guard
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
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      )
    else {
      return nil
    }
    cache.insert(image, for: data)
    return image
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

private final class MediaArtworkCache: @unchecked Sendable {
  private final class ImageBox {
    let image: CGImage

    init(_ image: CGImage) {
      self.image = image
    }
  }

  private let storage = NSCache<NSData, ImageBox>()

  init() {
    storage.countLimit = 8
    storage.totalCostLimit = 24_000_000
  }

  func image(for data: Data) -> CGImage? {
    storage.object(forKey: data as NSData)?.image
  }

  func insert(_ image: CGImage, for data: Data) {
    storage.setObject(
      ImageBox(image),
      forKey: data as NSData,
      cost: image.bytesPerRow * image.height
    )
  }
}
