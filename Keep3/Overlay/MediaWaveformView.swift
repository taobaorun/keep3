import SwiftUI

struct MediaWaveformView: View {
  let seed: String
  let isPlaying: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(
      .animation(
        minimumInterval: 1 / 12,
        paused: reduceMotion || !isPlaying
      )
    ) { context in
      HStack(alignment: .center, spacing: 2) {
        ForEach(0..<9, id: \.self) { index in
          Capsule()
            .frame(
              width: 2,
              height: level(
                at: index,
                date: context.date,
                animated: !reduceMotion && isPlaying
              )
            )
        }
      }
    }
    .foregroundStyle(.white.opacity(0.82))
    .accessibilityHidden(true)
  }

  private func level(
    at index: Int,
    date: Date,
    animated: Bool
  ) -> CGFloat {
    let scalarSeed = seed.utf8.reduce(0) {
      (($0 &* 31) &+ Int($1)) & 0x7FFF
    }
    let baseline = Double((scalarSeed + (index * 17)) % 9) / 8
    guard animated else {
      return 4 + (CGFloat(baseline) * 10)
    }
    let phase =
      date.timeIntervalSinceReferenceDate * 5
      + Double(index) * 0.82
      + baseline
    return 4 + (CGFloat((sin(phase) + 1) / 2) * 12)
  }
}
