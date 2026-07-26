import CoreGraphics
import Foundation
import ImageIO

struct MediaArtworkAccent: Equatable, Sendable {
  static let fallback = MediaArtworkAccent(
    red: 0.72,
    green: 0.72,
    blue: 0.72
  )

  let red: Double
  let green: Double
  let blue: Double
  let alpha: Double

  init(
    red: Double,
    green: Double,
    blue: Double,
    alpha: Double = 1
  ) {
    self.red = min(max(red, 0), 1)
    self.green = min(max(green, 0), 1)
    self.blue = min(max(blue, 0), 1)
    self.alpha = min(max(alpha, 0), 1)
  }

  var contrastAgainstBlack: Double {
    (relativeLuminance + 0.05) / 0.05
  }

  private var relativeLuminance: Double {
    let compositedRed = red * alpha
    let compositedGreen = green * alpha
    let compositedBlue = blue * alpha
    return (0.2126 * Self.linearized(compositedRed))
      + (0.7152 * Self.linearized(compositedGreen))
      + (0.0722 * Self.linearized(compositedBlue))
  }

  private static func linearized(_ component: Double) -> Double {
    if component <= 0.04045 {
      return component / 12.92
    }
    return pow((component + 0.055) / 1.055, 2.4)
  }
}

struct ResolvedMediaArtwork: @unchecked Sendable {
  let image: CGImage?
  let accent: MediaArtworkAccent
}

enum MediaArtworkDecoder {
  static let maximumInputBytes = MediaSession.maximumArtworkBytes
  static let maximumSourceDimension = 8_192
  static let maximumSourcePixels = 16_000_000
  static let thumbnailDimension = 512
  private static let resolver = MediaArtworkResolver()

  static func decode(_ data: Data?) -> CGImage? {
    resolve(data).image
  }

  static func resolve(_ data: Data?) -> ResolvedMediaArtwork {
    resolver.resolve(data)
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

}

final class MediaArtworkResolver: @unchecked Sendable {
  private let cache = MediaArtworkCache()
  private let lock = NSLock()
  private var extractionCount = 0

  var accentExtractionCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return extractionCount
  }

  func resolve(_ data: Data?) -> ResolvedMediaArtwork {
    guard let data else {
      return ResolvedMediaArtwork(image: nil, accent: .fallback)
    }

    lock.lock()
    defer { lock.unlock() }

    if let cached = cache.artwork(for: data) {
      return cached
    }

    let fallback = ResolvedMediaArtwork(image: nil, accent: .fallback)
    guard
      MediaArtworkDecoder.isMetadataAllowed(
        byteCount: data.count,
        frameCount: 1
      ),
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else {
      cache.insert(fallback, for: data)
      return fallback
    }

    let frameCount = CGImageSourceGetCount(source)
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(
        source,
        0,
        nil
      ) as? [CFString: Any],
      let width = Self.number(properties[kCGImagePropertyPixelWidth]),
      let height = Self.number(properties[kCGImagePropertyPixelHeight]),
      MediaArtworkDecoder.isMetadataAllowed(
        byteCount: data.count,
        frameCount: frameCount,
        width: width,
        height: height
      )
    else {
      cache.insert(fallback, for: data)
      return fallback
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize:
        MediaArtworkDecoder.thumbnailDimension,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      )
    else {
      cache.insert(fallback, for: data)
      return fallback
    }

    extractionCount += 1
    let artwork = ResolvedMediaArtwork(
      image: image,
      accent: MediaArtworkAccentExtractor.accent(from: image)
    )
    cache.insert(artwork, for: data)
    return artwork
  }

  private static func number(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
  }
}

private enum MediaArtworkAccentExtractor {
  private static let sampleDimension = 12
  private static let hueBucketCount = 12
  private static let minimumAlpha = 0.2
  private static let minimumSaturation = 0.12
  private static let minimumRelativeLuminance = 0.100_001

  private struct Bucket {
    var weight = 0.0
    var red = 0.0
    var green = 0.0
    var blue = 0.0
  }

  static func accent(from image: CGImage) -> MediaArtworkAccent {
    let bytesPerRow = sampleDimension * 4
    var pixels = [UInt8](
      repeating: 0,
      count: bytesPerRow * sampleDimension
    )
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: &pixels,
        width: sampleDimension,
        height: sampleDimension,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo:
          CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder32Big.rawValue
      )
    else {
      return .fallback
    }

    context.interpolationQuality = .low
    context.setBlendMode(.copy)
    context.draw(
      image,
      in: CGRect(
        x: 0,
        y: 0,
        width: sampleDimension,
        height: sampleDimension
      )
    )

    var buckets = Array(
      repeating: Bucket(),
      count: hueBucketCount
    )
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      let alpha = Double(pixels[offset + 3]) / 255
      guard alpha >= minimumAlpha else {
        continue
      }
      let red = min(Double(pixels[offset]) / 255 / alpha, 1)
      let green = min(Double(pixels[offset + 1]) / 255 / alpha, 1)
      let blue = min(Double(pixels[offset + 2]) / 255 / alpha, 1)
      let maximum = max(red, green, blue)
      let minimum = min(red, green, blue)
      let saturation =
        maximum > 0 ? (maximum - minimum) / maximum : 0
      guard saturation >= minimumSaturation else {
        continue
      }

      let bucketIndex = min(
        Int(hue(red: red, green: green, blue: blue) * Double(hueBucketCount)),
        hueBucketCount - 1
      )
      let weight = alpha * (0.5 + saturation)
      buckets[bucketIndex].weight += weight
      buckets[bucketIndex].red += red * weight
      buckets[bucketIndex].green += green * weight
      buckets[bucketIndex].blue += blue * weight
    }

    guard
      let dominant = buckets.max(by: { $0.weight < $1.weight }),
      dominant.weight > 0
    else {
      return .fallback
    }
    return readableAccent(
      red: dominant.red / dominant.weight,
      green: dominant.green / dominant.weight,
      blue: dominant.blue / dominant.weight
    )
  }

  private static func hue(
    red: Double,
    green: Double,
    blue: Double
  ) -> Double {
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum
    guard delta > 0 else {
      return 0
    }

    let rawHue: Double
    if maximum == red {
      rawHue = ((green - blue) / delta).truncatingRemainder(
        dividingBy: 6
      )
    } else if maximum == green {
      rawHue = ((blue - red) / delta) + 2
    } else {
      rawHue = ((red - green) / delta) + 4
    }
    let normalized = rawHue / 6
    return normalized < 0 ? normalized + 1 : normalized
  }

  private static func readableAccent(
    red: Double,
    green: Double,
    blue: Double
  ) -> MediaArtworkAccent {
    let original = MediaArtworkAccent(
      red: red,
      green: green,
      blue: blue
    )
    guard
      original.contrastAgainstBlack
        < ((minimumRelativeLuminance + 0.05) / 0.05)
    else {
      return original
    }

    var lowerBound = 0.0
    var upperBound = 1.0
    for _ in 0..<24 {
      let amount = (lowerBound + upperBound) / 2
      let candidate = MediaArtworkAccent(
        red: red + ((1 - red) * amount),
        green: green + ((1 - green) * amount),
        blue: blue + ((1 - blue) * amount)
      )
      if candidate.contrastAgainstBlack >= 3.000_02 {
        upperBound = amount
      } else {
        lowerBound = amount
      }
    }
    let amount = upperBound
    return MediaArtworkAccent(
      red: red + ((1 - red) * amount),
      green: green + ((1 - green) * amount),
      blue: blue + ((1 - blue) * amount)
    )
  }
}

private final class MediaArtworkCache: @unchecked Sendable {
  private final class ArtworkBox {
    let artwork: ResolvedMediaArtwork

    init(_ artwork: ResolvedMediaArtwork) {
      self.artwork = artwork
    }
  }

  private let storage = NSCache<NSData, ArtworkBox>()

  init() {
    storage.countLimit = 8
    storage.totalCostLimit = 24_000_000
  }

  func artwork(for data: Data) -> ResolvedMediaArtwork? {
    storage.object(forKey: data as NSData)?.artwork
  }

  func insert(_ artwork: ResolvedMediaArtwork, for data: Data) {
    let imageCost =
      artwork.image.map { $0.bytesPerRow * $0.height } ?? 0
    storage.setObject(
      ArtworkBox(artwork),
      forKey: data as NSData,
      cost: data.count + imageCost
    )
  }
}
