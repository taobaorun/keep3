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

  private lazy var rotationCoordinator = RotationCoordinator {
    [weak self] itemID in
    self?.showRotatedItem(itemID)
  }
  private lazy var surfaceModeCoordinator = SurfaceModeCoordinator(
    onPresentation: { [weak self] presentation in
      self?.render(presentation)
    },
    onMediaOwnershipChange: { [weak self] ownsSurface in
      if ownsSurface {
        self?.pauseRotation()
      } else {
        self?.resumeRotation()
      }
    }
  )
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
    preferences.onChange = { [weak self] in
      self?.applyPreferences()
    }
    appModel.onStateChange = { [weak self] state in
      self?.update(state)
    }
    update(appModel.state)
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
    guard case let .focus(payload) = presentation else {
      topSurfaceController.remove()
      return
    }

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
      onScroll: { [weak self] delta, phase in
        self?.interactionModel.scroll(delta: delta, phase: phase)
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
