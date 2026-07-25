import AppKit

@MainActor
final class TopSurfaceController {
  private(set) var panel: TopSurfacePanel?

  func showOnPrimaryDisplay(
    content: TopSurfaceContent,
    metrics: SurfaceMetrics = .standard,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (CGFloat, TopSurfaceGesturePhase) -> Void = { _, _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
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
    show(
      layout: geometry.layout(isExpanded: content.isExpanded),
      content: content,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem
    )
  }

  func showMediaOnPrimaryDisplay(
    payload: MediaSurfacePayload,
    metrics: SurfaceMetrics = .media,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
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
    showMedia(
      layout: geometry.layout(isExpanded: payload.isExpanded),
      payload: payload,
      onHoverChanged: onHoverChanged,
      onActivateSurface: onActivateSurface,
      onAction: onAction
    )
  }

  func show(
    layout: SurfaceLayout,
    content: TopSurfaceContent,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (CGFloat, TopSurfaceGesturePhase) -> Void = { _, _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
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
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem
    )
  }

  func showMedia(
    layout: SurfaceLayout,
    payload: MediaSurfacePayload,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onAction: @escaping (MediaSurfaceAction) -> Void = { _ in }
  ) {
    let presentationStyle =
      layout.obstructionSize.map {
        TopSurfacePresentationStyle.notchAttached(notchSize: $0)
      } ?? .floatingCapsule

    let surfacePanel: TopSurfacePanel
    if let panel {
      surfacePanel = panel
    } else {
      surfacePanel = TopSurfacePanel(
        contentRect: layout.panelFrame,
        surfaceFrameInPanel: layout.surfaceFrameInPanel,
        mediaPayload: payload,
        presentationStyle: presentationStyle,
        onHoverChanged: onHoverChanged,
        onActivateSurface: onActivateSurface,
        onMediaAction: onAction
      )
      panel = surfacePanel
    }

    surfacePanel.update(
      mediaPayload: payload,
      presentationStyle: presentationStyle,
      surfaceFrameInPanel: layout.surfaceFrameInPanel,
      onHoverChanged: onHoverChanged,
      onActivateSurface: onActivateSurface,
      onMediaAction: onAction
    )
    surfacePanel.setFrame(layout.panelFrame, display: true)
    surfacePanel.orderFrontRegardless()
  }

  func show(
    frame: CGRect,
    content: TopSurfaceContent,
    presentationStyle: TopSurfacePresentationStyle = .floatingCapsule,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (CGFloat, TopSurfaceGesturePhase) -> Void = { _, _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
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
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem
    )
  }

  private func present(
    layout: SurfaceLayout,
    content: TopSurfaceContent,
    presentationStyle: TopSurfacePresentationStyle,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (CGFloat, TopSurfaceGesturePhase) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onDismiss: @escaping () -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void
  ) {
    let surfacePanel: TopSurfacePanel

    if let panel {
      surfacePanel = panel
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
        onDismiss: onDismiss,
        onNavigate: onNavigate,
        onOpenItem: onOpenItem
      )
      panel = surfacePanel
    }

    surfacePanel.update(
      content: content,
      presentationStyle: presentationStyle,
      surfaceFrameInPanel: layout.surfaceFrameInPanel,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem
    )
    surfacePanel.setFrame(layout.panelFrame, display: true)
    surfacePanel.orderFrontRegardless()
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
    panel?.orderOut(nil)
    panel = nil
  }
}
