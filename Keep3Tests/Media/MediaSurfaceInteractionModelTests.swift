import XCTest

@testable import Keep3

@MainActor
final class MediaSurfaceInteractionModelTests: XCTestCase {
  func testConfirmedTrackChangeShowsMetadataPeekWithoutFullExpansion() {
    let scheduler = ManualMediaInteractionTimerScheduler()
    var peeks: [MediaTrackPeek?] = []
    let model = MediaSurfaceInteractionModel(
      scheduler: scheduler,
      onTrackPeek: { peeks.append($0) }
    )

    model.receiveConfirmedTrackChange(
      .init(direction: .next, snapshot: snapshot(title: "First"))
    )

    XCTAssertEqual(peeks.compactMap { $0 }.last?.title, "First")
    XCTAssertEqual(peeks.compactMap { $0 }.last?.artist, "Artist")
    XCTAssertEqual(scheduler.activeDelays, [2])

    scheduler.fireNext()

    XCTAssertNil(peeks.last!)
  }

  func testEachConfirmedTrackChangeRestartsQuickPeek() {
    let scheduler = ManualMediaInteractionTimerScheduler()
    var peeks: [MediaTrackPeek?] = []
    let model = MediaSurfaceInteractionModel(
      scheduler: scheduler,
      onTrackPeek: { peeks.append($0) }
    )

    model.receiveConfirmedTrackChange(
      .init(
        direction: .next,
        snapshot: snapshot(title: "First", contentRevision: 1)
      )
    )
    model.receiveConfirmedTrackChange(
      .init(
        direction: .previous,
        snapshot: snapshot(title: "First", contentRevision: 2)
      )
    )

    XCTAssertEqual(peeks.compactMap { $0 }.count, 2)
    XCTAssertEqual(scheduler.activeTimerCount, 1)
  }

  func testDisablingQuickPeekClearsTemporaryMetadata() {
    let scheduler = ManualMediaInteractionTimerScheduler()
    var peeks: [MediaTrackPeek?] = []
    let model = MediaSurfaceInteractionModel(
      scheduler: scheduler,
      onTrackPeek: { peeks.append($0) }
    )

    model.receiveConfirmedTrackChange(
      .init(direction: .next, snapshot: snapshot(title: "First"))
    )
    model.updatePreferences(
      isQuickPeekEnabled: false,
      quickPeekDuration: 2
    )

    XCTAssertNil(peeks.last!)
    XCTAssertEqual(scheduler.activeTimerCount, 0)
  }

  private func snapshot(
    title: String,
    contentRevision: UInt64 = 1
  ) -> MediaSessionSnapshot {
    MediaSessionSnapshot(
      session: MediaSession.normalize(
        .init(
          sessionID: "session",
          sourceBundleIdentifier: "com.netease.163music",
          title: title,
          artist: "Artist",
          album: "Album",
          duration: 240,
          progress: 12,
          capabilities: MediaCapability.allCases.map(\.rawValue)
        )
      )!,
      playbackState: .playing,
      subscriptionEpoch: 1,
      capabilityRevision: 1,
      contentRevision: contentRevision
    )
  }
}

@MainActor
private final class ManualMediaInteractionTimerScheduler:
  AppTimerScheduling
{
  private final class Timer: AppTimerCancellation {
    let delay: TimeInterval
    let action: () -> Void
    var isCancelled = false

    init(delay: TimeInterval, action: @escaping () -> Void) {
      self.delay = delay
      self.action = action
    }

    func cancel() {
      isCancelled = true
    }
  }

  private var timers: [Timer] = []

  var activeDelays: [TimeInterval] {
    timers.filter { !$0.isCancelled }.map(\.delay)
  }

  var activeTimerCount: Int {
    activeDelays.count
  }

  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any AppTimerCancellation {
    let timer = Timer(delay: delay, action: action)
    timers.append(timer)
    return timer
  }

  func fireNext() {
    guard let timer = timers.first(where: { !$0.isCancelled }) else {
      return
    }
    timer.isCancelled = true
    timer.action()
  }
}
