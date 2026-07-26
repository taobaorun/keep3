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
  private let launchAtLoginController = LaunchAtLoginController.live()
  private let topSurfaceController = TopSurfaceController()
  private var state = Keep3State()
  private var isSurfaceAvailable = true
  private var activeMediaEpoch: UInt64?
  private var currentMediaSnapshot: MediaSessionSnapshot?
  private var mediaLifecycleGeneration: UInt64 = 0
  private var isMediaSubscriptionStarting = false
  private let mediaLifecycleQueue = SerialMediaLifecycleQueue()
  private var mediaGestureRecognizer = MediaGestureRecognizer()
  private var isMediaOwningSurface = false
  private lazy var editorWindowController = EditorWindowController(
    model: appModel,
    preferences: preferences,
    mediaPreferences: mediaPreferences,
    launchAtLoginController: launchAtLoginController
  )

  private lazy var interactionModel = TopSurfaceInteractionModel(
    onIntent: { [weak self] intent in
      self?.surfaceModeCoordinator.handleInteraction(intent)
    },
    onPauseRotation: { [weak self] in
      self?.pauseRotation()
    },
    onResumeRotation: { [weak self] in
      self?.resumeRotation()
    },
    onOpenItem: { [weak self] itemID in
      self?.openEditor(for: itemID)
    }
  )
  private lazy var mediaSurfaceInteractionModel =
    MediaSurfaceInteractionModel { [weak self] isExpanded, reason in
      self?.surfaceModeCoordinator.updateMediaExpansion(
        isExpanded: isExpanded,
        reason: reason
      )
    }
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
    }
  )

  private lazy var rotationCoordinator = RotationCoordinator {
    [weak self] itemID in
    self?.showRotatedItem(itemID)
  }
  private lazy var surfaceModeCoordinator = SurfaceModeCoordinator(
    onPresentation: { [weak self] presentation in
      self?.render(presentation)
    },
    onMediaOwnershipChange: { [weak self] ownsSurface in
      self?.handleMediaOwnershipChange(ownsSurface)
    }
  )
  private lazy var workspaceApplicationObserver =
    WorkspaceApplicationObserver { [weak self] bundleIdentifier in
      self?.surfaceModeCoordinator.updateFrontmostBundleIdentifier(
        bundleIdentifier
      )
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
    preferences.onChange = { [weak self] in
      self?.applyPreferences()
    }
    mediaPreferences.onChange = { [weak self] in
      self?.applyMediaPreferences()
    }
    appModel.onStateChange = { [weak self] state in
      self?.update(state)
    }
    update(appModel.state)
    applyMediaPreferences()
    editorWindowController.showEditor()
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
    editorWindowController.showEditor()
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    displayLifecycleObserver.stop()
    workspaceApplicationObserver.stop()
    stopMediaSubscription()
    surfaceModeCoordinator.setSurfaceAvailable(false)
    interactionModel.suspend()
    rotationCoordinator.pause()
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
    interactionModel.update(
      itemIDs: state.items.map(\.id),
      currentFocusID: state.currentFocusID
    )
    rotationCoordinator.setRotationEnabled(
      preferences.isAutomaticRotationEnabled
    )
    rotationCoordinator.update(
      itemIDs: state.items.map(\.id),
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
      expansionTrigger: mediaPreferences.expansionTrigger,
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
    surfaceModeCoordinator.setSurfaceAvailable(false)
    interactionModel.suspend()
    rotationCoordinator.pause()
    stopMediaSubscription()
    topSurfaceController.remove()
  }

  private func activateSurface() {
    guard !isSurfaceAvailable else {
      return
    }
    isSurfaceAvailable = true
    resetSurfaceToCurrentFocus()
    surfaceModeCoordinator.setSurfaceAvailable(true)
    surfaceModeCoordinator.reconcileAfterAvailability()
    if mediaPreferences.isMediaFirstEnabled {
      startMediaSubscription()
    }
  }

  private func pauseRotation() {
    rotationCoordinator.pause()
  }

  private func resumeRotation() {
    rotationCoordinator.resumeResettingToCurrentFocus()
  }

  private func showRotatedItem(_ itemID: UUID?) {
    interactionModel.showRotatedItem(itemID)
  }

  private func render(_ presentation: TopSurfacePresentation) {
    switch presentation {
    case .hidden:
      topSurfaceController.remove()
    case .media(let payload):
      renderMedia(payload)
    case .focus(let payload):
      renderFocus(payload)
    }
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
        if isInside {
          self?.interactionModel.pointerEntered()
        } else {
          self?.interactionModel.pointerExited()
        }
      },
      onScroll: { [weak self] event in
        guard event.momentumPhase == .none else {
          return
        }
        let delta =
          event.isPrecise
          ? event.focusNavigationDelta
          : event.focusNavigationDelta * 20
        self?.interactionModel.scroll(
          delta: delta,
          phase: event.physicalPhase
        )
      },
      onActivateSurface: { [weak self] in
        self?.interactionModel.activateSurface()
      },
      onRequestKeyboardNavigation: { [weak self] in
        self?.topSurfaceController.beginKeyboardNavigation()
      },
      onDismiss: { [weak self] in
        self?.interactionModel.dismissExpandedSurface()
      },
      onNavigate: { [weak self] direction in
        self?.interactionModel.browse(direction)
      },
      onOpenItem: { [weak self] in
        self?.interactionModel.activateVisibleItem()
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
      onHoverChanged: { [weak self] isInside in
        if isInside {
          self?.mediaSurfaceInteractionModel.pointerEntered()
        } else {
          self?.mediaSurfaceInteractionModel.pointerExited()
        }
      },
      onScroll: { [weak self] event in
        self?.handleMediaScroll(event)
      },
      onActivateSurface: { [weak self] in
        self?.mediaSurfaceInteractionModel.activateSurface()
      },
      onAction: { [weak self] action in
        self?.handleMediaAction(action)
      }
    )
  }

  private func handlePendingMediaActionChange(
    _ action: MediaSurfaceAction?
  ) {
    surfaceModeCoordinator.setMediaControlsEnabled(action == nil)
  }

  private func handleMediaOwnershipChange(_ ownsSurface: Bool) {
    isMediaOwningSurface = ownsSurface
    if ownsSurface {
      pauseRotation()
      if let currentMediaSnapshot {
        mediaGestureRecognizer.updateSession(
          currentMediaSnapshot.session.sessionID
        )
        mediaCommandCoordinator.updateContext(
          snapshot: currentMediaSnapshot,
          isMediaActive: true
        )
      }
    } else {
      interactionModel.synchronizeToCurrentFocusWithoutPresentation()
      rotationCoordinator.resumeAfterCurrentFocusWasPresented()
      mediaGestureRecognizer.cancel()
      mediaCommandCoordinator.updateContext(
        snapshot: currentMediaSnapshot,
        isMediaActive: false
      )
    }
  }

  private func handleMediaScroll(_ event: SurfaceScrollEvent) {
    guard isMediaOwningSurface,
      let direction = mediaGestureRecognizer.handle(event)
    else {
      return
    }
    handleMediaAction(direction.action)
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
    mediaGestureRecognizer.cancel()
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
    mediaSurfaceInteractionModel.receive(snapshot)
    surfaceModeCoordinator.receiveMediaSnapshot(snapshot)

    guard let snapshot else {
      mediaGestureRecognizer.cancel()
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
    mediaGestureRecognizer.updateSession(
      isMediaOwningSurface ? snapshot.session.sessionID : nil
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
        width: max(360, preferences.capsuleWidth),
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
    guard
      let suiteName = environment["KEEP3_UI_TEST_DEFAULTS_SUITE"],
      !suiteName.isEmpty,
      let defaults = UserDefaults(suiteName: suiteName)
    else {
      return MediaPreferences.live()
    }
    return MediaPreferences(defaults: defaults)
  }
}
