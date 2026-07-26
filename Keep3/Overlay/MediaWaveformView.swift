import SwiftUI

struct MediaWaveformStyle: Equatable {
  let barCount: Int
  let barWidth: CGFloat
  let spacing: CGFloat
  let minimumHeight: CGFloat
  let heightRange: CGFloat

  static let regular = MediaWaveformStyle(
    barCount: 9,
    barWidth: 2,
    spacing: 2,
    minimumHeight: 4,
    heightRange: 12
  )

  static let notchedCompact = MediaWaveformStyle(
    barCount: 6,
    barWidth: 1.5,
    spacing: 1.5,
    minimumHeight: 3,
    heightRange: 7
  )

  static let expanded = MediaWaveformStyle(
    barCount: 6,
    barWidth: 2,
    spacing: 2,
    minimumHeight: 4,
    heightRange: 10
  )

  var intrinsicWidth: CGFloat {
    guard barCount > 0 else {
      return 0
    }
    return (CGFloat(barCount) * barWidth)
      + (CGFloat(barCount - 1) * spacing)
  }

  var maximumHeight: CGFloat {
    minimumHeight + heightRange
  }
}

struct MediaWaveformView: View {
  let isPlaying: Bool
  let style: MediaWaveformStyle
  let accent: MediaArtworkAccent
  let scalarSeed: Int

  init(
    seed: String,
    isPlaying: Bool,
    style: MediaWaveformStyle = .regular,
    accent: MediaArtworkAccent
  ) {
    self.isPlaying = isPlaying
    self.style = style
    self.accent = accent
    scalarSeed = seed.utf8.reduce(0) {
      (($0 &* 31) &+ Int($1)) & 0x7FFF
    }
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(
      .animation(
        minimumInterval: 1 / 12,
        paused: reduceMotion || !isPlaying
      )
    ) { context in
      HStack(alignment: .center, spacing: style.spacing) {
        ForEach(0..<style.barCount, id: \.self) { index in
          Capsule()
            .frame(
              width: style.barWidth,
              height: level(
                at: index,
                date: context.date,
                animated: !reduceMotion && isPlaying
              )
            )
        }
      }
    }
    .foregroundStyle(
      Color(
        .sRGB,
        red: accent.red,
        green: accent.green,
        blue: accent.blue,
        opacity: accent.alpha
      )
    )
    .accessibilityHidden(true)
  }

  private func level(
    at index: Int,
    date: Date,
    animated: Bool
  ) -> CGFloat {
    let baseline = Double((scalarSeed + (index * 17)) % 9) / 8
    guard animated else {
      return style.minimumHeight
        + (CGFloat(baseline) * max(0, style.heightRange - 2))
    }
    let phase =
      date.timeIntervalSinceReferenceDate * 5
      + Double(index) * 0.82
      + baseline
    return style.minimumHeight
      + (CGFloat((sin(phase) + 1) / 2) * style.heightRange)
  }
}
