import EventKit
import SwiftUI

@main
struct Keep3App: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let appModel = AppDelegate.makeAppModel()
  private let preferences = AppDelegate.makePreferences()
  private let mediaPreferences = AppDelegate.makeMediaPreferences()
  private let calendarPreferences = AppDelegate.makeCalendarPreferences()
  private let launchAtLoginController = LaunchAtLoginController.live()
  private let topSurfaceController = TopSurfaceController()
  private let surfaceHapticFeedback = AppKitSurfaceHapticFeedback()
  private var state = Keep3State()
  private var isSurfaceAvailable = true
  private var activeMediaEpoch: UInt64?
  private var currentMediaSnapshot: MediaSessionSnapshot?
  private var mediaLifecycleGeneration: UInt64 = 0
  private var isMediaSubscriptionStarting = false
  private var mediaApplicationLifecycleTask: Task<Void, Never>?
  private let mediaLifecycleQueue = SerialMediaLifecycleQueue()
  private var surfaceGestureRecognizer = SurfaceGestureRecognizer()
  private var isMediaOwningSurface = false
  private var sourceFocusPayload: FocusSurfacePayload?
  private var sourceMediaPayload: MediaSurfacePayload?
  private var calendarState: CalendarSessionState = .disabled
  private var calendarRevision: UInt64 = 0
  private var calendarStoreObserver: NSObjectProtocol?
  private lazy var editorWindowController = EditorWindowController(
    model: appModel,
    preferences: preferences,
    mediaPreferences: mediaPreferences,
    calendarPreferences: calendarPreferences,
    calendarCoordinator: calendarSessionCoordinator,
    launchAtLoginController: launchAtLoginController
  )

  private lazy var interactionModel = TopSurfaceInteractionModel(
    onIntent: { [weak self] intent in
      self?.handleFocusInteraction(intent)
    },
    onPauseRotation: { [weak self] in
      self?.rotationCoordinator.setFocusInteractionPaused(true)
    },
    onResumeRotation: { [weak self] in
      self?.rotationCoordinator.setFocusInteractionPaused(false)
    },
    onOpenItem: { [weak self] itemID in
      self?.openEditor(for: itemID)
    }
  )
  private lazy var mediaSurfaceInteractionModel =
    MediaSurfaceInteractionModel(
      onTrackPeek: { [weak self] peek in
        self?.surfaceModeCoordinator.updateMediaTrackPeek(peek)
      }
    )
  private lazy var mediaAdapter: any MediaSessionAdapter =
    makeMediaAdapter()
  private lazy var mediaSessionCoordinator = MediaSessionCoordinator {
    [weak self] snapshot in
    self?.handleMediaSnapshot(snapshot)
  }
  private lazy var mediaCommandCoordinator = MediaCommandCoordinator(
    sender: mediaAdapter,
    onPendingActionChange: { [weak self] action in
      self?.handlePendingMediaActionChange(action)
    },
    onConfirmedTrackChange: { [weak self] change in
      self?.mediaSurfaceInteractionModel.receiveConfirmedTrackChange(change)
    }
  )

  private lazy var rotationCoordinator = RotationCoordinator {
    [weak self] itemID in
    self?.showRotatedItem(itemID)
  }
  private lazy var surfaceModeCoordinator = SurfaceModeCoordinator(
    onPresentation: { [weak self] presentation in
      self?.handleSourcePresentation(presentation)
    },
    onFocusPayloadChange: { [weak self] payload in
      self?.handleSourceFocusPayload(payload)
    }
  )
  private lazy var surfaceNavigationCoordinator =
    SurfaceNavigationCoordinator(
      onStateChange: { [weak self] state in
        self?.handleNavigationState(state)
      }
    )
  private lazy var calendarSessionCoordinator = CalendarSessionCoordinator(
    provider: AppDelegate.makeCalendarProvider(),
    onStateChange: { [weak self] state in
      self?.handleCalendarState(state)
    }
  )
  private lazy var workspaceApplicationObserver =
    WorkspaceApplicationObserver { [weak self] bundleIdentifier in
      self?.surfaceModeCoordinator.updateFrontmostBundleIdentifier(
        bundleIdentifier
      )
    } onApplicationLifecycleChange: { [weak self] bundleIdentifier in
      self?.handleApplicationLifecycleChange(bundleIdentifier)
    }
  private lazy var displayLifecycleCoordinator = DisplayLifecycleCoordinator(
    onRefresh: { [weak self] in
      self?.refreshSurface()
    },
    onDeactivate: { [weak self] in
      self?.deactivateSurface()
    },
    onActivate: { [weak self] in
      self?.activateSurface()
    }
  )
  private lazy var displayLifecycleObserver = DisplayLifecycleObserver {
    [weak self] event in
    self?.handleDisplayLifecycleEvent(event)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    displayLifecycleObserver.start()
    workspaceApplicationObserver.start()
    calendarStoreObserver = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.isSurfaceAvailable,
          self.calendarPreferences.isEnabled
        else {
          return
        }
        self.calendarSessionCoordinator.refresh()
      }
    }
    preferences.onChange = { [weak self] in
      self?.applyPreferences()
    }
    mediaPreferences.onChange = { [weak self] in
      self?.applyMediaPreferences()
    }
    calendarPreferences.onChange = { [weak self] in
      self?.applyCalendarPreferences()
    }
    appModel.onStateChange = { [weak self] state in
      self?.update(state)
    }
    update(appModel.state)
    applyMediaPreferences()
    applyCalendarPreferences()
    applyUITestSurfaceLevel()
  }

  func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool {
    false
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    launchAtLoginController.refresh()
    guard !topSurfaceController.isKeyboardNavigationActive else {
      return true
    }
    editorWindowController.showEditor()
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    displayLifecycleObserver.stop()
    workspaceApplicationObserver.stop()
    mediaApplicationLifecycleTask?.cancel()
    mediaApplicationLifecycleTask = nil
    if let calendarStoreObserver {
      NotificationCenter.default.removeObserver(calendarStoreObserver)
      self.calendarStoreObserver = nil
    }
    calendarSessionCoordinator.invalidateAndClear()
    stopMediaSubscription()
    surfaceNavigationCoordinator.setSurfaceAvailable(false)
    surfaceModeCoordinator.setSurfaceAvailable(false)
    interactionModel.suspend()
    rotationCoordinator.setSurfaceAvailable(false)
    topSurfaceController.remove()
  }

  private func update(_ state: Keep3State) {
    self.state = state
    guard isSurfaceAvailable else {
      return
    }
    resetSurfaceToCurrentFocus()
  }

  private func resetSurfaceToCurrentFocus() {
    interactionModel.setExpansionTrigger(preferences.expansionTrigger)
    surfaceModeCoordinator.updateDesignatedFocusID(state.currentFocusID)
    let itemIDs = state.items.map(\.id)
    surfaceNavigationCoordinator.setAvailability(
      !itemIDs.isEmpty,
      for: .priorities
    )
    interactionModel.update(
      itemIDs: itemIDs,
      currentFocusID: state.currentFocusID
    )
    let navigation = surfaceNavigationCoordinator.state
    interactionModel.synchronizeUnifiedExpansion(
      navigation.selectedComponent == .priorities
        && navigation.level == .expanded
    )
    rotationCoordinator.setFocusInteractionPaused(
      navigation.selectedComponent == .priorities
        && navigation.level == .expanded
    )
    rotationCoordinator.setRotationEnabled(
      preferences.isAutomaticRotationEnabled
    )
    rotationCoordinator.update(
      itemIDs: itemIDs,
      currentFocusID: state.currentFocusID,
      durations: preferences.rotationDurations
    )
  }

  private func applyPreferences() {
    guard isSurfaceAvailable else {
      return
    }
    resetSurfaceToCurrentFocus()
  }

  private func applyMediaPreferences() {
    surfaceModeCoordinator.updateMediaPolicy(mediaPreferences.sourcePolicy)
    surfaceModeCoordinator.updateMediaAppearance(mediaPreferences.appearance)
    mediaSurfaceInteractionModel.updatePreferences(
      isQuickPeekEnabled: mediaPreferences.isQuickPeekEnabled,
      quickPeekDuration: mediaPreferences.quickPeekDuration
    )

    if mediaPreferences.isMediaFirstEnabled {
      if activeMediaEpoch == nil, !isMediaSubscriptionStarting {
        startMediaSubscription()
      }
    } else if activeMediaEpoch != nil || isMediaSubscriptionStarting {
      stopMediaSubscription()
    }
  }

  private func applyCalendarPreferences() {
    calendarSessionCoordinator.setEnabled(calendarPreferences.isEnabled)
  }

  private func handleApplicationLifecycleChange(
    _ bundleIdentifier: String?
  ) {
    guard let bundleIdentifier,
      MediaRemoteDormantPlayerPolicy.supportedBundleIdentifiers.contains(
        bundleIdentifier
      ),
      isSurfaceAvailable,
      mediaPreferences.isMediaFirstEnabled
    else {
      return
    }
    mediaApplicationLifecycleTask?.cancel()
    mediaApplicationLifecycleTask = Task { @MainActor [weak self] in
      await self?.reconcileMediaApplicationLifecycle(
        bundleIdentifier: bundleIdentifier
      )
    }
  }

  private func reconcileMediaApplicationLifecycle(
    bundleIdentifier: String
  ) async {
    let retryDelays: [Duration] = [
      .milliseconds(500),
      .seconds(2),
      .seconds(4),
    ]
    for delay in retryDelays {
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, isSurfaceAvailable,
        mediaPreferences.isMediaFirstEnabled
      else {
        return
      }
      let isApplicationRunning =
        NSRunningApplication.runningApplications(
          withBundleIdentifier: bundleIdentifier
        ).contains(where: { !$0.isTerminated })
      let hasMatchingSession =
        currentMediaSnapshot?.session.sourceBundleIdentifier
        == bundleIdentifier
      guard
        MediaRemoteApplicationLifecyclePolicy.requiresRefresh(
          isApplicationRunning: isApplicationRunning,
          hasAnySession: currentMediaSnapshot != nil,
          hasMatchingSession: hasMatchingSession
        )
      else {
        return
      }
      stopMediaSubscription()
      startMediaSubscription()
    }
  }

  private func handleDisplayLifecycleEvent(_ event: DisplayLifecycleEvent) {
    displayLifecycleCoordinator.handle(event)
  }

  private func refreshSurface() {
    guard isSurfaceAvailable else {
      return
    }
    resetSurfaceToCurrentFocus()
  }

  private func deactivateSurface() {
    guard isSurfaceAvailable else {
      return
    }
    isSurfaceAvailable = false
    surfaceNavigationCoordinator.setSurfaceAvailable(false)
    surfaceModeCoordinator.setSurfaceAvailable(false)
    calendarSessionCoordinator.invalidateAndClear()
    surfaceGestureRecognizer.cancel()
    interactionModel.suspend()
    rotationCoordinator.setSurfaceAvailable(false)
    stopMediaSubscription()
    topSurfaceController.remove()
  }

  private func activateSurface() {
    guard !isSurfaceAvailable else {
      return
    }
    isSurfaceAvailable = true
    resetSurfaceToCurrentFocus()
    surfaceNavigationCoordinator.setSurfaceAvailable(true)
    surfaceModeCoordinator.setSurfaceAvailable(true)
    surfaceNavigationCoordinator.reconcileAfterAvailability()
    surfaceModeCoordinator.reconcileAfterAvailability()
    rotationCoordinator.setSurfaceAvailable(true)
    if calendarPreferences.isEnabled {
      calendarSessionCoordinator.refresh()
    }
    if mediaPreferences.isMediaFirstEnabled {
      startMediaSubscription()
    }
  }

  private func showRotatedItem(_ itemID: UUID?) {
    interactionModel.showRotatedItem(itemID)
  }

  private func handleFocusInteraction(
    _ intent: TopSurfaceInteractionIntent
  ) {
    surfaceModeCoordinator.handleInteraction(intent)
  }

  private func handleSourcePresentation(
    _ presentation: TopSurfacePresentation
  ) {
    switch presentation {
    case .hidden:
      let mediaSessionID = sourceMediaPayload?.sessionID
      sourceFocusPayload = nil
      sourceMediaPayload = nil
      if let mediaSessionID {
        surfaceNavigationCoordinator.endMediaSession(mediaSessionID)
      } else {
        renderSelectedSurface()
      }
    case .focus(let payload):
      let mediaSessionID = sourceMediaPayload?.sessionID
      sourceFocusPayload = payload
      sourceMediaPayload = nil
      if let mediaSessionID {
        surfaceNavigationCoordinator.endMediaSession(mediaSessionID)
      } else {
        renderSelectedSurface()
      }
    case .media(let payload):
      let isNewSession = sourceMediaPayload?.sessionID != payload.sessionID
      let didStartPlaying =
        payload.playbackState == .playing
        && sourceMediaPayload?.playbackState != .playing
      sourceFocusPayload =
        surfaceModeCoordinator.currentFocusPayload ?? sourceFocusPayload
      sourceMediaPayload = payload
      if isNewSession {
        surfaceNavigationCoordinator.beginMediaSession(
          payload.sessionID,
          automaticallySelect: payload.playbackState == .playing
        )
      } else {
        surfaceNavigationCoordinator.beginMediaSession(
          payload.sessionID,
          automaticallySelect: didStartPlaying
        )
        renderSelectedSurface()
      }
    case .calendar:
      break
    }
  }

  private func handleSourceFocusPayload(_ payload: FocusSurfacePayload) {
    sourceFocusPayload = payload
    guard sourceMediaPayload != nil,
      surfaceNavigationCoordinator.state.selectedComponent == .priorities
    else {
      return
    }
    renderSelectedSurface()
  }

  private func handleCalendarState(_ state: CalendarSessionState) {
    calendarState = state
    calendarRevision &+= 1
    let availabilityChanged =
      surfaceNavigationCoordinator.isAvailable(.calendar)
      != state.isComponentAvailable
    surfaceNavigationCoordinator.setAvailability(
      state.isComponentAvailable,
      for: .calendar
    )
    if !availabilityChanged {
      renderSelectedSurface()
    }
  }

  private func handleNavigationState(_ state: SurfaceNavigationState) {
    let isFocusExpanded =
      state.selectedComponent == .priorities
      && state.level == .expanded
    if state.selectedComponent == .priorities {
      interactionModel.synchronizeUnifiedExpansion(
        state.level == .expanded
      )
    } else {
      interactionModel.synchronizeToCurrentFocusWithoutPresentation()
    }
    rotationCoordinator.setFocusInteractionPaused(isFocusExpanded)
    handleMediaOwnershipChange(
      state.isPresented
        && state.selectedComponent == .media
        && sourceMediaPayload != nil
    )
    renderSelectedSurface()
  }

  private func renderSelectedSurface() {
    let navigation = surfaceNavigationCoordinator.state
    guard isSurfaceAvailable, navigation.isPresented else {
      topSurfaceController.remove()
      synchronizeSurfaceGestureContext()
      return
    }

    let level = navigation.effectiveLevel
    switch navigation.selectedComponent {
    case .priorities:
      guard let sourceFocusPayload else {
        topSurfaceController.remove()
        synchronizeSurfaceGestureContext()
        return
      }
      renderFocus(
        FocusSurfacePayload(
          visibleItemID: sourceFocusPayload.visibleItemID,
          isExpanded: level == .expanded,
          level: level,
          revision: sourceFocusPayload.revision,
          expansionReason:
            navigation.isHoverPreviewed
            ? .hover : level == .expanded ? .manual : .none,
          isHovered: navigation.isHovering
        )
      )
    case .media:
      guard let sourceMediaPayload else {
        topSurfaceController.remove()
        synchronizeSurfaceGestureContext()
        return
      }
      renderMedia(
        MediaSurfacePayload(
          sessionID: sourceMediaPayload.sessionID,
          contentRevision: sourceMediaPayload.contentRevision,
          isExpanded: level == .expanded,
          level: level,
          areControlsEnabled: sourceMediaPayload.areControlsEnabled,
          session: sourceMediaPayload.session,
          playbackState: sourceMediaPayload.playbackState,
          capabilityRevision: sourceMediaPayload.capabilityRevision,
          expansionReason:
            navigation.isHoverPreviewed
            ? .hover : level == .expanded ? .manual : .none,
          appearance: sourceMediaPayload.appearance,
          trackChangeDirection: sourceMediaPayload.trackChangeDirection,
          trackPeek: sourceMediaPayload.trackPeek,
          isHovered: navigation.isHovering
        )
      )
    case .calendar:
      renderCalendar(
        CalendarSurfacePayload(
          state: calendarState,
          level: level,
          revision: calendarRevision,
          isHovered: navigation.isHovering
        )
      )
    }
    synchronizeSurfaceGestureContext()
  }

  private func synchronizeSurfaceGestureContext() {
    let navigation = surfaceNavigationCoordinator.state
    guard navigation.isPresented,
      let interactionFrame =
        topSurfaceController.visibleInteractionFrameInScreen
    else {
      surfaceGestureRecognizer.updateContext(nil)
      return
    }
    surfaceGestureRecognizer.updateContext(
      SurfaceGestureContext(
        component: navigation.selectedComponent,
        level: navigation.level,
        generation: navigation.generation,
        mediaSessionID:
          navigation.selectedComponent == .media
          ? sourceMediaPayload?.sessionID : nil,
        interactionFrameInScreen: interactionFrame
      )
    )
  }

  private func renderFocus(_ payload: FocusSurfacePayload) {
    guard isSurfaceAvailable,
      let id = payload.visibleItemID,
      let position = state.items.firstIndex(where: { $0.id == id }),
      let item = state.items.first(where: { $0.id == id })
    else {
      topSurfaceController.remove()
      return
    }

    let content = TopSurfaceContent(
      item: item,
      position: position + 1,
      itemCount: state.items.count,
      isCurrentFocus: id == state.currentFocusID,
      presentation: payload,
      appearance: SurfaceAppearance(
        backgroundOpacity: preferences.backgroundOpacity
      )
    )
    topSurfaceController.showOnPrimaryDisplay(
      content: content,
      metrics: surfaceMetrics,
      onHoverChanged: { [weak self] isInside in
        self?.handleSurfaceHoverChange(isInside)
      },
      onScroll: { [weak self] event in
        self?.handleSurfaceScroll(event)
      },
      onActivateSurface: { [weak self] in
        self?.activateSurfaceForKeyboardNavigation()
      },
      onRequestKeyboardNavigation: { [weak self] in
        self?.topSurfaceController.beginKeyboardNavigation()
      },
      onSurfaceNavigation: { [weak self] intent in
        self?.surfaceNavigationCoordinator.apply(intent)
      },
      onDismiss: { [weak self] in
        self?.dismissSurfaceNavigation()
      },
      onNavigate: { [weak self] direction in
        self?.interactionModel.browse(direction)
      },
      onOpenItem: { [weak self] in
        guard let self else {
          return
        }
        self.topSurfaceController.endKeyboardNavigation(
          restoringPreviousApplication: false
        )
        self.interactionModel.activateVisibleItem()
      }
    )
  }

  private func renderMedia(_ payload: MediaSurfacePayload) {
    guard isSurfaceAvailable else {
      topSurfaceController.remove()
      return
    }
    topSurfaceController.showMediaOnPrimaryDisplay(
      payload: payload,
      focusMetrics: surfaceMetrics,
      onHoverChanged: { [weak self] isInside in
        self?.handleSurfaceHoverChange(isInside)
      },
      onScroll: { [weak self] event in
        self?.handleSurfaceScroll(event)
      },
      onActivateSurface: { [weak self] in
        self?.activateSurfaceForKeyboardNavigation()
      },
      onRequestKeyboardNavigation: { [weak self] in
        self?.topSurfaceController.beginKeyboardNavigation()
      },
      onSurfaceNavigation: { [weak self] intent in
        self?.surfaceNavigationCoordinator.apply(intent)
      },
      onDismiss: { [weak self] in
        self?.dismissSurfaceNavigation()
      },
      onNavigate: { [weak self] direction in
        self?.handleMediaAction(
          direction == .previous ? .previous : .next
        )
      },
      onAction: { [weak self] action in
        self?.handleMediaAction(action)
      }
    )
  }

  private func renderCalendar(_ payload: CalendarSurfacePayload) {
    guard isSurfaceAvailable else {
      topSurfaceController.remove()
      return
    }
    topSurfaceController.showCalendarOnPrimaryDisplay(
      payload: payload,
      metrics: surfaceMetrics,
      onHoverChanged: { [weak self] isInside in
        self?.handleSurfaceHoverChange(isInside)
      },
      onScroll: { [weak self] event in
        self?.handleSurfaceScroll(event)
      },
      onActivateSurface: { [weak self] in
        self?.activateSurfaceForKeyboardNavigation()
      },
      onRequestKeyboardNavigation: { [weak self] in
        self?.topSurfaceController.beginKeyboardNavigation()
      },
      onSurfaceNavigation: { [weak self] intent in
        self?.surfaceNavigationCoordinator.apply(intent)
      },
      onDismiss: { [weak self] in
        self?.dismissSurfaceNavigation()
      }
    )
  }

  private func dismissSurfaceNavigation() {
    topSurfaceController.endKeyboardNavigation()
    surfaceNavigationCoordinator.setLevel(.compact)
  }

  private func activateSurfaceForKeyboardNavigation() {
    surfaceNavigationCoordinator.setLevel(.expanded)
    topSurfaceController.beginKeyboardNavigation()
  }

  private func handleSurfaceHoverChange(_ isInside: Bool) {
    let wasHovering = surfaceNavigationCoordinator.state.isHovering
    surfaceNavigationCoordinator.setHovering(isInside)
    if isInside && !wasHovering {
      surfaceHapticFeedback.performHoverFeedback()
    }
  }

  private func handlePendingMediaActionChange(
    _ action: MediaSurfaceAction?
  ) {
    if action != nil {
      mediaSurfaceInteractionModel.reset()
    }
    surfaceModeCoordinator.setMediaControlsEnabled(action == nil)
    surfaceModeCoordinator.updateMediaTrackChangeDirection(nil)
  }

  private func handleMediaOwnershipChange(_ ownsSurface: Bool) {
    rotationCoordinator.setMediaSurfacePresented(ownsSurface)
    guard isMediaOwningSurface != ownsSurface else {
      return
    }
    isMediaOwningSurface = ownsSurface
    if ownsSurface {
      if let currentMediaSnapshot {
        mediaCommandCoordinator.updateContext(
          snapshot: currentMediaSnapshot,
          isMediaActive: true
        )
      }
    } else {
      interactionModel.synchronizeToCurrentFocusWithoutPresentation()
      mediaSurfaceInteractionModel.reset()
      mediaCommandCoordinator.updateContext(
        snapshot: currentMediaSnapshot,
        isMediaActive: false
      )
    }
  }

  private func handleSurfaceScroll(_ event: SurfaceScrollEvent) {
    let recognition = surfaceGestureRecognizer.recognize(event)
    if let feedbackIntent = recognition.feedbackIntent {
      performSurfaceGestureFeedback(for: feedbackIntent)
    }
    guard let intent = recognition.committedIntent else {
      return
    }
    switch intent {
    case .previousTrack:
      handleMediaAction(.previous)
    case .nextTrack:
      handleMediaAction(.next)
    case .advanceDepth, .retreatDepth, .previousComponent, .nextComponent:
      surfaceNavigationCoordinator.apply(intent)
    }
  }

  private func performSurfaceGestureFeedback(
    for intent: SurfaceGestureIntent
  ) {
    switch intent {
    case .advanceDepth, .previousComponent, .nextComponent:
      surfaceHapticFeedback.performNavigationGesture()
    case .retreatDepth:
      let navigation = surfaceNavigationCoordinator.state
      guard navigation.level != .hardware || navigation.isHoverPreviewed else {
        return
      }
      surfaceHapticFeedback.performNavigationGesture()
    case .previousTrack:
      guard
        currentMediaSnapshot?.session.capabilities.contains(.previous) == true
      else {
        return
      }
      surfaceHapticFeedback.performTrackGesture()
    case .nextTrack:
      guard
        currentMediaSnapshot?.session.capabilities.contains(.next) == true
      else {
        return
      }
      surfaceHapticFeedback.performTrackGesture()
    }
  }

  private func handleMediaAction(_ action: MediaSurfaceAction) {
    if action == .hideSource {
      mediaPreferences.setSuppressed(
        currentMediaSnapshot?.session.sourceBundleIdentifier,
        isSuppressed: true
      )
      return
    }
    if case .copySource(let url) = action {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([url as NSURL])
      return
    }
    Task { @MainActor [weak self] in
      _ = await self?.mediaCommandCoordinator.perform(action)
    }
  }

  private func startMediaSubscription() {
    guard isSurfaceAvailable,
      mediaPreferences.isMediaFirstEnabled,
      activeMediaEpoch == nil,
      !isMediaSubscriptionStarting
    else {
      return
    }
    isMediaSubscriptionStarting = true
    mediaLifecycleGeneration &+= 1
    let generation = mediaLifecycleGeneration
    mediaLifecycleQueue.enqueue { [weak self] in
      guard let self else {
        return
      }
      let epoch = await mediaSessionCoordinator.beginSubscription()
      guard generation == mediaLifecycleGeneration,
        activeMediaEpoch == nil
      else {
        return
      }
      isMediaSubscriptionStarting = false
      activeMediaEpoch = epoch
      surfaceModeCoordinator.beginMediaEpoch(epoch)
      let report = await mediaAdapter.start()
      guard generation == mediaLifecycleGeneration else {
        return
      }
      if report.status == .unavailable {
        stopMediaSubscription()
      }
    }
  }

  private func stopMediaSubscription() {
    mediaLifecycleGeneration &+= 1
    isMediaSubscriptionStarting = false
    let epoch = activeMediaEpoch
    activeMediaEpoch = nil
    currentMediaSnapshot = nil
    mediaSurfaceInteractionModel.reset()
    mediaCommandCoordinator.cancel()
    if let epoch {
      surfaceModeCoordinator.endMediaEpoch(epoch)
    }
    mediaLifecycleQueue.enqueue { [mediaAdapter, mediaSessionCoordinator] in
      await mediaAdapter.stop()
      await mediaSessionCoordinator.endSubscription()
    }
  }

  private func receiveAdapterSnapshot(
    _ adapterSnapshot: MediaAdapterSnapshot?
  ) {
    guard let epoch = activeMediaEpoch else {
      return
    }
    Task { [mediaSessionCoordinator] in
      if let adapterSnapshot {
        await mediaSessionCoordinator.receive(
          MediaSessionSnapshot(
            session: adapterSnapshot.session,
            playbackState: adapterSnapshot.playbackState,
            subscriptionEpoch: epoch,
            capabilityRevision: adapterSnapshot.capabilityRevision,
            contentRevision: adapterSnapshot.contentRevision
          )
        )
      } else {
        await mediaSessionCoordinator.receiveUnavailable(epoch: epoch)
      }
    }
  }

  private func handleMediaSnapshot(_ snapshot: MediaSessionSnapshot?) {
    currentMediaSnapshot = snapshot
    surfaceModeCoordinator.receiveMediaSnapshot(snapshot)

    guard let snapshot else {
      mediaCommandCoordinator.updateContext(
        snapshot: nil,
        isMediaActive: false
      )
      return
    }
    mediaCommandCoordinator.receive(snapshot)
    mediaCommandCoordinator.updateContext(
      snapshot: snapshot,
      isMediaActive: isMediaOwningSurface
    )
  }

  private func makeMediaAdapter() -> any MediaSessionAdapter {
    let delivery: MediaAdapterSnapshotDelivery = { [weak self] snapshot in
      self?.receiveAdapterSnapshot(snapshot)
    }
    #if DEBUG
      if ProcessInfo.processInfo.environment[
        "KEEP3_UI_TEST_MEDIA_FIXTURE"
      ] == "playing" {
        return MediaFixtureAdapter(onSnapshot: delivery)
      }
    #endif
    return MediaRemoteAdapter(onSnapshot: delivery)
  }

  private func openEditor(for itemID: UUID) {
    appModel.selectItem(id: itemID)
    editorWindowController.showEditor()
  }

  private var surfaceMetrics: SurfaceMetrics {
    SurfaceMetrics(
      compactSize: CGSize(width: preferences.capsuleWidth, height: 44),
      expandedSize: CGSize(
        width: preferences.capsuleWidth
          + SurfaceMetrics.focusExpandedHorizontalGrowth,
        height: 216
      ),
      floatingTopSpacing: 8
    )
  }

  private static func makeAppModel() -> AppModel {
    let environment = ProcessInfo.processInfo.environment
    guard
      let path = environment["KEEP3_UI_TEST_STATE_PATH"],
      !path.isEmpty
    else {
      return AppModel.live()
    }
    return AppModel(
      stateStore: JSONStateStore(fileURL: URL(fileURLWithPath: path))
    )
  }

  private static func makePreferences() -> AppPreferences {
    let environment = ProcessInfo.processInfo.environment
    guard
      let suiteName = environment["KEEP3_UI_TEST_DEFAULTS_SUITE"],
      !suiteName.isEmpty,
      let defaults = UserDefaults(suiteName: suiteName)
    else {
      return AppPreferences.live()
    }
    return AppPreferences(defaults: defaults)
  }

  private static func makeMediaPreferences() -> MediaPreferences {
    let environment = ProcessInfo.processInfo.environment
    let preferences: MediaPreferences
    if let suiteName = environment["KEEP3_UI_TEST_DEFAULTS_SUITE"],
      !suiteName.isEmpty,
      let defaults = UserDefaults(suiteName: suiteName)
    {
      preferences = MediaPreferences(defaults: defaults)
    } else {
      preferences = MediaPreferences.live()
    }
    #if DEBUG
      if let rawValue = environment["KEEP3_UI_TEST_MEDIA_ENABLED"],
        let isEnabled = Bool(rawValue)
      {
        preferences.setMediaFirstEnabled(isEnabled)
      }
    #endif
    return preferences
  }

  private static func makeCalendarPreferences() -> CalendarPreferences {
    let environment = ProcessInfo.processInfo.environment
    let preferences: CalendarPreferences
    if let suiteName = environment["KEEP3_UI_TEST_DEFAULTS_SUITE"],
      !suiteName.isEmpty,
      let defaults = UserDefaults(suiteName: suiteName)
    {
      preferences = CalendarPreferences(defaults: defaults)
    } else {
      preferences = CalendarPreferences.live()
    }
    #if DEBUG
      if let rawValue = environment["KEEP3_UI_TEST_CALENDAR_ENABLED"],
        let isEnabled = Bool(rawValue)
      {
        preferences.setEnabled(isEnabled)
      }
    #endif
    return preferences
  }

  private static func makeCalendarProvider() -> any CalendarEventProviding {
    #if DEBUG
      if let fixture = ProcessInfo.processInfo.environment[
        "KEEP3_UI_TEST_CALENDAR_FIXTURE"
      ] {
        return CalendarUITestFixtureProvider(fixture: fixture)
      }
    #endif
    return EventKitCalendarAdapter()
  }

  private func applyUITestSurfaceLevel() {
    #if DEBUG
      guard
        let rawLevel = ProcessInfo.processInfo.environment[
          "KEEP3_UI_TEST_SURFACE_LEVEL"
        ],
        let level = SurfaceLevel(rawValue: rawLevel)
      else {
        return
      }
      surfaceNavigationCoordinator.setLevel(level)
    #endif
  }
}

#if DEBUG
  @MainActor
  private final class CalendarUITestFixtureProvider:
    CalendarEventProviding
  {
    private let status: CalendarAuthorizationState

    init(fixture: String) {
      status = fixture == "authorized" ? .fullAccess : .denied
    }

    func authorizationStatus() -> CalendarAuthorizationState {
      status
    }

    func requestFullAccess() async throws -> Bool {
      status == .fullAccess
    }

    func events(
      from startDate: Date,
      through _: Date
    ) async throws -> [CalendarEvent] {
      guard status == .fullAccess else {
        return []
      }
      return [
        CalendarEvent(
          id: "ui-fixture-event",
          title: "UI Fixture Event",
          startDate: startDate.addingTimeInterval(15 * 60),
          endDate: startDate.addingTimeInterval(45 * 60),
          isAllDay: false
        )
      ]
    }
  }
#endif
