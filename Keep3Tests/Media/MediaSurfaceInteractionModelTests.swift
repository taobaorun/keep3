import XCTest

@testable import Keep3

@MainActor
final class MediaSurfaceInteractionModelTests: XCTestCase {
  func testNewPlayingContentQuickPeeksThenCollapses() {
    let scheduler = ManualMediaInteractionTimerScheduler()
    var expansions: [(Bool, SurfaceExpansionReason)] = []
    let model = MediaSurfaceInteractionModel(
      scheduler: scheduler
    ) { isExpanded, reason in
      expansions.append((isExpanded, reason))
    }

    model.receive(snapshot(title: "First"))

    XCTAssertEqual(expansions.count, 1)
    XCTAssertTrue(expansions[0].0)
    XCTAssertEqual(expansions[0].1, .quickPeek)
    XCTAssertEqual(scheduler.activeDelays, [2])

    scheduler.fireNext()

    XCTAssertEqual(expansions.count, 2)
    XCTAssertFalse(expansions[1].0)
    XCTAssertEqual(expansions[1].1, .none)
  }

  func testProgressOnlyRevisionDoesNotRestartQuickPeek() {
    let scheduler = ManualMediaInteractionTimerScheduler()
    var expansions: [(Bool, SurfaceExpansionReason)] = []
    let model = MediaSurfaceInteractionModel(
      scheduler: scheduler
    ) { isExpanded, reason in
      expansions.append((isExpanded, reason))
    }

    model.receive(snapshot(title: "First", contentRevision: 1))
    model.receive(snapshot(title: "First", contentRevision: 2))

    XCTAssertEqual(expansions.count, 1)
    XCTAssertEqual(scheduler.activeTimerCount, 1)
  }

  func testHoverSupersedesQuickPeekAndOwnsCollapse() {
    let scheduler = ManualMediaInteractionTimerScheduler()
    var expansions: [(Bool, SurfaceExpansionReason)] = []
    let model = MediaSurfaceInteractionModel(
      scheduler: scheduler
    ) { isExpanded, reason in
      expansions.append((isExpanded, reason))
    }

    model.receive(snapshot(title: "First"))
    model.pointerEntered()

    XCTAssertEqual(expansions.last?.1, .hover)
    XCTAssertEqual(scheduler.activeTimerCount, 0)

    model.pointerExited()

    XCTAssertEqual(expansions.last?.0, false)
    XCTAssertEqual(
      expansions.last?.1,
      SurfaceExpansionReason.none
    )
  }

  func testDisablingQuickPeekCollapsesOnlyTemporaryExpansion() {
    let scheduler = ManualMediaInteractionTimerScheduler()
    var expansions: [(Bool, SurfaceExpansionReason)] = []
    let model = MediaSurfaceInteractionModel(
      scheduler: scheduler
    ) { isExpanded, reason in
      expansions.append((isExpanded, reason))
    }

    model.receive(snapshot(title: "First"))
    model.updatePreferences(
      expansionTrigger: .hover,
      isQuickPeekEnabled: false,
      quickPeekDuration: 2
    )

    XCTAssertEqual(expansions.last?.0, false)
    XCTAssertEqual(
      expansions.last?.1,
      SurfaceExpansionReason.none
    )
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
