import AppKit

@MainActor
final class TopSurfaceController {
  private(set) var panel: TopSurfacePanel?
  var onVisibleInteractionFrameChanged: () -> Void = {}

  var visibleInteractionFrameInScreen: CGRect? {
    guard let panel, panel.isVisible else {
      return nil
    }
    return panel.convertToScreen(panel.presentedSurfaceFrameInPanel)
  }

  func showOnPrimaryDisplay(
    content: TopSurfaceContent,
    metrics: SurfaceMetrics = .standard,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void = { _ in },
    onOpenItem: @escaping () -> Void = {}
  ) {
    guard let screen = NSScreen.screens.first else {
      remove()
      return
    }

    let geometry = DisplayGeometry(
      descriptor: DisplayDescriptor(screen: screen),
      metrics: metrics
    )
    let activeLayout = geometry.layout(level: content.level)
    show(
      layout: geometry.sharedEnvelopeLayout(
        containing: activeLayout,
        companionMetrics: .media
      ),
      content: content,
      transitionIntent: transitionIntent,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem
    )
  }

  func showMediaOnPrimaryDisplay(
    payload: MediaSurfacePayload,
    metrics: SurfaceMetrics = .media,
    focusMetrics: SurfaceMetrics = .standard,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void = { _ in },
    onAction: @escaping (MediaSurfaceAction) -> Void = { _ in }
  ) {
    guard let screen = NSScreen.screens.first else {
      remove()
      return
    }

    let geometry = DisplayGeometry(
      descriptor: DisplayDescriptor(screen: screen),
      metrics: metrics
    )
    let activeLayout = geometry.mediaLayout(
      level: payload.level,
      trackChangeDirection:
        payload.trackChangeDirection ?? payload.trackPeek?.direction,
      showsTrackPeek: payload.trackPeek != nil
    )
    showMedia(
      layout: geometry.sharedEnvelopeLayout(
        containing: activeLayout,
        companionMetrics: focusMetrics
      ),
      payload: payload,
      transitionIntent: transitionIntent,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onAction: onAction
    )
  }

  func showCalendarOnPrimaryDisplay(
    payload: CalendarSurfacePayload,
    metrics: SurfaceMetrics = .standard,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {}
  ) {
    guard let screen = NSScreen.screens.first else {
      remove()
      return
    }

    let geometry = DisplayGeometry(
      descriptor: DisplayDescriptor(screen: screen),
      metrics: metrics
    )
    let activeLayout = geometry.layout(level: payload.level)
    showCalendar(
      layout: geometry.sharedEnvelopeLayout(
        containing: activeLayout,
        companionMetrics: .media
      ),
      payload: payload,
      transitionIntent: transitionIntent,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onDismiss: onDismiss
    )
  }

  func show(
    layout: SurfaceLayout,
    content: TopSurfaceContent,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void = { _ in },
    onOpenItem: @escaping () -> Void = {}
  ) {
    let presentationStyle =
      layout.obstructionSize.map {
        TopSurfacePresentationStyle.notchAttached(notchSize: $0)
      } ?? .floatingCapsule

    present(
      layout: layout,
      content: content,
      presentationStyle: presentationStyle,
      transitionIntent: transitionIntent,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem
    )
  }

  func showMedia(
    layout: SurfaceLayout,
    payload: MediaSurfacePayload,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void = { _ in },
    onAction: @escaping (MediaSurfaceAction) -> Void = { _ in }
  ) {
    let presentationStyle =
      layout.obstructionSize.map {
        TopSurfacePresentationStyle.notchAttached(notchSize: $0)
      } ?? .floatingCapsule

    let surfacePanel: TopSurfacePanel
    if let panel {
      surfacePanel = panel
      surfacePanel.setFrame(layout.panelFrame, display: true)
      surfacePanel.update(
        mediaPayload: payload,
        presentationStyle: presentationStyle,
        surfaceFrameInPanel: layout.surfaceFrameInPanel,
        transitionIntent: transitionIntent,
        onHoverChanged: onHoverChanged,
        onScroll: onScroll,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onSurfaceNavigation: onSurfaceNavigation,
        onDismiss: onDismiss,
        onNavigate: onNavigate,
        onMediaAction: onAction
      )
    } else {
      surfacePanel = TopSurfacePanel(
        contentRect: layout.panelFrame,
        surfaceFrameInPanel: layout.surfaceFrameInPanel,
        mediaPayload: payload,
        presentationStyle: presentationStyle,
        onHoverChanged: onHoverChanged,
        onScroll: onScroll,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onSurfaceNavigation: onSurfaceNavigation,
        onDismiss: onDismiss,
        onNavigate: onNavigate,
        onMediaAction: onAction
      )
      panel = surfacePanel
    }
    connectPresentedGeometryCallback(to: surfacePanel)
    surfacePanel.orderFrontRegardless()
  }

  func showCalendar(
    layout: SurfaceLayout,
    payload: CalendarSurfacePayload,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {}
  ) {
    let presentationStyle =
      layout.obstructionSize.map {
        TopSurfacePresentationStyle.notchAttached(notchSize: $0)
      } ?? .floatingCapsule

    let surfacePanel: TopSurfacePanel
    if let panel {
      surfacePanel = panel
      surfacePanel.setFrame(layout.panelFrame, display: true)
      surfacePanel.update(
        calendarPayload: payload,
        presentationStyle: presentationStyle,
        surfaceFrameInPanel: layout.surfaceFrameInPanel,
        transitionIntent: transitionIntent,
        onHoverChanged: onHoverChanged,
        onScroll: onScroll,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onSurfaceNavigation: onSurfaceNavigation,
        onDismiss: onDismiss
      )
    } else {
      surfacePanel = TopSurfacePanel(
        contentRect: layout.panelFrame,
        surfaceFrameInPanel: layout.surfaceFrameInPanel,
        calendarPayload: payload,
        presentationStyle: presentationStyle,
        onHoverChanged: onHoverChanged,
        onScroll: onScroll,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onSurfaceNavigation: onSurfaceNavigation,
        onDismiss: onDismiss
      )
      panel = surfacePanel
    }
    connectPresentedGeometryCallback(to: surfacePanel)
    surfacePanel.orderFrontRegardless()
  }

  func show(
    frame: CGRect,
    content: TopSurfaceContent,
    presentationStyle: TopSurfacePresentationStyle = .floatingCapsule,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void = { _ in },
    onOpenItem: @escaping () -> Void = {}
  ) {
    let obstructionSize: CGSize?
    switch presentationStyle {
    case .notchAttached(let notchSize):
      obstructionSize = notchSize
    case .floatingCapsule:
      obstructionSize = nil
    }
    present(
      layout: SurfaceLayout(
        panelFrame: frame,
        surfaceFrameInPanel: CGRect(origin: .zero, size: frame.size),
        obstructionSize: obstructionSize
      ),
      content: content,
      presentationStyle: presentationStyle,
      transitionIntent: transitionIntent,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem
    )
  }

  private func present(
    layout: SurfaceLayout,
    content: TopSurfaceContent,
    presentationStyle: TopSurfacePresentationStyle,
    transitionIntent: SurfaceTransitionIntent,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (SurfaceScrollEvent) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void,
    onDismiss: @escaping () -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void
  ) {
    let surfacePanel: TopSurfacePanel

    if let panel {
      surfacePanel = panel
      surfacePanel.setFrame(layout.panelFrame, display: true)
      surfacePanel.update(
        content: content,
        presentationStyle: presentationStyle,
        surfaceFrameInPanel: layout.surfaceFrameInPanel,
        transitionIntent: transitionIntent,
        onHoverChanged: onHoverChanged,
        onScroll: onScroll,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onSurfaceNavigation: onSurfaceNavigation,
        onDismiss: onDismiss,
        onNavigate: onNavigate,
        onOpenItem: onOpenItem
      )
    } else {
      surfacePanel = TopSurfacePanel(
        contentRect: layout.panelFrame,
        surfaceFrameInPanel: layout.surfaceFrameInPanel,
        content: content,
        presentationStyle: presentationStyle,
        onHoverChanged: onHoverChanged,
        onScroll: onScroll,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onSurfaceNavigation: onSurfaceNavigation,
        onDismiss: onDismiss,
        onNavigate: onNavigate,
        onOpenItem: onOpenItem
      )
      panel = surfacePanel
    }
    connectPresentedGeometryCallback(to: surfacePanel)
    surfacePanel.orderFrontRegardless()
  }

  private func connectPresentedGeometryCallback(
    to panel: TopSurfacePanel
  ) {
    panel.onPresentedGeometryChanged = { [weak self] in
      self?.onVisibleInteractionFrameChanged()
    }
  }

  func reposition(frame: CGRect) {
    panel?.setFrame(frame, display: true)
  }

  func beginKeyboardNavigation() {
    panel?.setKeyboardNavigationEnabled(true)
  }

  func endKeyboardNavigation() {
    panel?.setKeyboardNavigationEnabled(false)
  }

  func remove() {
    panel?.setKeyboardNavigationEnabled(false)
    panel?.cancelTransitionForLifecycle()
    panel?.orderOut(nil)
    panel = nil
  }
}
