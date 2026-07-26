import AppKit
import SwiftUI

enum TopSurfaceKeyboardCommand: Equatable, Sendable {
  case previous
  case next
  case dismiss
  case openItem

  init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
    let meaningfulModifiers = modifiers.intersection(
      .deviceIndependentFlagsMask
    ).subtracting([.capsLock, .numericPad, .function])
    guard meaningfulModifiers.isEmpty else {
      return nil
    }

    switch keyCode {
    case 123:
      self = .previous
    case 124:
      self = .next
    case 53:
      self = .dismiss
    case 36, 76:
      self = .openItem
    default:
      return nil
    }
  }
}

@MainActor
final class TopSurfacePanel: NSPanel {
  override var canBecomeKey: Bool { keyboardNavigationEnabled }
  override var canBecomeMain: Bool { false }

  private let eventView: TopSurfaceEventView
  private var panelContent: PanelContent
  private(set) var renderedPresentationStyle: TopSurfacePresentationStyle
  private(set) var renderedSurfaceFrameInPanel: CGRect
  private var keyboardNavigationEnabled = false
  private var keyboardEventMonitor: Any?

  var renderedContent: TopSurfaceContent {
    guard case .focus(let content) = panelContent else {
      preconditionFailure("The panel is currently rendering media")
    }
    return content
  }

  var renderedMediaPayload: MediaSurfacePayload? {
    guard case .media(let payload) = panelContent else {
      return nil
    }
    return payload
  }

  convenience init(
    contentRect: CGRect,
    surfaceFrameInPanel: CGRect? = nil,
    content: TopSurfaceContent,
    presentationStyle: TopSurfacePresentationStyle = .floatingCapsule,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onDismiss: @escaping () -> Void = {},
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void = { _ in },
    onOpenItem: @escaping () -> Void = {}
  ) {
    self.init(
      contentRect: contentRect,
      surfaceFrameInPanel: surfaceFrameInPanel,
      panelContent: .focus(content),
      presentationStyle: presentationStyle,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem,
      onMediaAction: { _ in }
    )
  }

  convenience init(
    contentRect: CGRect,
    surfaceFrameInPanel: CGRect? = nil,
    mediaPayload: MediaSurfacePayload,
    presentationStyle: TopSurfacePresentationStyle = .floatingCapsule,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onMediaAction: @escaping (MediaSurfaceAction) -> Void = { _ in }
  ) {
    self.init(
      contentRect: contentRect,
      surfaceFrameInPanel: surfaceFrameInPanel,
      panelContent: .media(mediaPayload),
      presentationStyle: presentationStyle,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: {},
      onDismiss: {},
      onNavigate: { _ in },
      onOpenItem: {},
      onMediaAction: onMediaAction
    )
  }

  private init(
    contentRect: CGRect,
    surfaceFrameInPanel: CGRect?,
    panelContent: PanelContent,
    presentationStyle: TopSurfacePresentationStyle,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (SurfaceScrollEvent) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onDismiss: @escaping () -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void,
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) {
    let resolvedSurfaceFrame =
      surfaceFrameInPanel ?? CGRect(origin: .zero, size: contentRect.size)
    self.panelContent = panelContent
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = resolvedSurfaceFrame
    eventView = TopSurfaceEventView(
      frame: CGRect(origin: .zero, size: contentRect.size),
      activeFrame: resolvedSurfaceFrame,
      rootView: Self.rootView(
        for: panelContent,
        presentationStyle: presentationStyle,
        surfaceSize: resolvedSurfaceFrame.size,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onNavigate: onNavigate,
        onOpenItem: onOpenItem,
        onMediaAction: onMediaAction
      )
    )

    super.init(
      contentRect: contentRect,
      styleMask: [
        .borderless,
        .nonactivatingPanel,
        .utilityWindow,
        .hudWindow,
      ],
      backing: .buffered,
      defer: false
    )

    isFloatingPanel = true
    level = .mainMenu + 3
    collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
      .ignoresCycle,
    ]
    becomesKeyOnlyIfNeeded = true
    hidesOnDeactivate = false
    canHide = false
    canBecomeVisibleWithoutLogin = false
    isReleasedWhenClosed = false
    isMovable = false
    isOpaque = false
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    backgroundColor = .clear
    hasShadow = presentationStyle.hasPanelShadow
    animationBehavior = .none

    eventView.autoresizingMask = [.width, .height]
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = onNavigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = onOpenItem
    eventView.updateActiveFrame(resolvedSurfaceFrame)
    contentView = eventView
    sharingType = .readOnly
  }

  func update(
    content: TopSurfaceContent,
    presentationStyle: TopSurfacePresentationStyle,
    surfaceFrameInPanel: CGRect,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (SurfaceScrollEvent) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onDismiss: @escaping () -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void
  ) {
    panelContent = .focus(content)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = onNavigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = onOpenItem
    eventView.updateActiveFrame(surfaceFrameInPanel)
    eventView.hostingView.rootView = Self.rootView(
      for: panelContent,
      presentationStyle: presentationStyle,
      surfaceSize: surfaceFrameInPanel.size,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem,
      onMediaAction: { _ in }
    )

    if !content.isExpanded {
      setKeyboardNavigationEnabled(false)
    }
  }

  func update(
    mediaPayload: MediaSurfacePayload,
    presentationStyle: TopSurfacePresentationStyle,
    surfaceFrameInPanel: CGRect,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (SurfaceScrollEvent) -> Void,
    onActivateSurface: @escaping () -> Void,
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) {
    panelContent = .media(mediaPayload)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = { _ in }
    eventView.onDismiss = {}
    eventView.onOpenItem = {}
    eventView.updateActiveFrame(surfaceFrameInPanel)
    eventView.hostingView.rootView = Self.rootView(
      for: panelContent,
      presentationStyle: presentationStyle,
      surfaceSize: surfaceFrameInPanel.size,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: {},
      onNavigate: { _ in },
      onOpenItem: {},
      onMediaAction: onMediaAction
    )
    setKeyboardNavigationEnabled(false)
  }

  private static func rootView(
    for content: PanelContent,
    presentationStyle: TopSurfacePresentationStyle,
    surfaceSize: CGSize,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void,
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) -> AnyView {
    switch content {
    case .focus(let focus):
      AnyView(
        TopSurfaceView(
          content: focus,
          presentationStyle: presentationStyle,
          surfaceSize: surfaceSize,
          onActivateSurface: onActivateSurface,
          onRequestKeyboardNavigation: onRequestKeyboardNavigation,
          onNavigate: onNavigate,
          onOpenItem: onOpenItem
        )
      )
    case .media(let media):
      AnyView(
        MediaSurfaceView(
          payload: media,
          presentationStyle: presentationStyle,
          surfaceSize: surfaceSize,
          onAction: onMediaAction,
          onActivateSurface: onActivateSurface
        )
      )
    }
  }

  func setKeyboardNavigationEnabled(
    _ isEnabled: Bool,
    activateApplication: Bool = true
  ) {
    keyboardNavigationEnabled = isEnabled

    guard isEnabled else {
      if let keyboardEventMonitor {
        NSEvent.removeMonitor(keyboardEventMonitor)
        self.keyboardEventMonitor = nil
      }
      if isKeyWindow {
        resignKey()
      }
      orderFrontRegardless()
      return
    }

    if activateApplication {
      NSApp.activate()
    }
    if keyboardEventMonitor == nil {
      keyboardEventMonitor = NSEvent.addLocalMonitorForEvents(
        matching: .keyDown
      ) { [weak self] event in
        guard let self, self.keyboardNavigationEnabled else {
          return event
        }
        return self.eventView.handleKeyboardEvent(event) ? nil : event
      }
    }
    makeKeyAndOrderFront(nil)
    makeFirstResponder(eventView)
    Task { @MainActor [weak self] in
      guard let self, self.keyboardNavigationEnabled else {
        return
      }
      self.makeFirstResponder(self.eventView)
    }
  }

  override func sendEvent(_ event: NSEvent) {
    if keyboardNavigationEnabled,
      event.type == .keyDown,
      eventView.handleKeyboardEvent(event)
    {
      return
    }
    super.sendEvent(event)
  }
}

private enum PanelContent {
  case focus(TopSurfaceContent)
  case media(MediaSurfacePayload)
}

@MainActor
private final class TopSurfaceEventView: NSView {
  override var acceptsFirstResponder: Bool { true }

  let hostingView: NSHostingView<AnyView>
  var onHoverChanged: (Bool) -> Void = { _ in }
  var onScroll: (SurfaceScrollEvent) -> Void = { _ in }
  var onNavigate: (TopSurfaceBrowseDirection) -> Void = { _ in }
  var onDismiss: () -> Void = {}
  var onOpenItem: () -> Void = {}

  private var hoverTrackingArea: NSTrackingArea?
  private var activeFrame: CGRect

  init(
    frame: CGRect,
    activeFrame: CGRect,
    rootView: AnyView
  ) {
    self.activeFrame = activeFrame
    hostingView = NSHostingView(rootView: rootView)
    super.init(frame: frame)

    hostingView.frame = bounds
    hostingView.autoresizingMask = [.width, .height]
    addSubview(hostingView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateActiveFrame(_ frame: CGRect) {
    guard activeFrame != frame else {
      return
    }
    activeFrame = frame
    updateTrackingAreas()
  }

  override func updateTrackingAreas() {
    if let hoverTrackingArea {
      removeTrackingArea(hoverTrackingArea)
    }

    let area = NSTrackingArea(
      rect: activeFrame,
      options: [.mouseEnteredAndExited, .activeAlways],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    hoverTrackingArea = area
    super.updateTrackingAreas()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard activeFrame.contains(point) else {
      return nil
    }
    return super.hitTest(point)
  }

  override func mouseEntered(with event: NSEvent) {
    onHoverChanged(true)
  }

  override func mouseExited(with event: NSEvent) {
    onHoverChanged(false)
  }

  override func scrollWheel(with event: NSEvent) {
    onScroll(
      SurfaceScrollEvent(
        deltaX: event.scrollingDeltaX,
        deltaY: event.scrollingDeltaY,
        isPrecise: event.hasPreciseScrollingDeltas,
        physicalPhase: physicalPhase(for: event.phase),
        momentumPhase: momentumPhase(for: event.momentumPhase)
      )
    )
  }

  override func swipe(with event: NSEvent) {
    guard event.deltaX != 0 else {
      return
    }
    onNavigate(event.deltaX > 0 ? .previous : .next)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    guard !handleKeyboardEvent(event) else {
      return
    }
    super.keyDown(with: event)
  }

  func handleKeyboardEvent(_ event: NSEvent) -> Bool {
    guard
      let command = TopSurfaceKeyboardCommand(
        keyCode: event.keyCode,
        modifiers: event.modifierFlags
      )
    else {
      return false
    }

    switch command {
    case .previous:
      onNavigate(.previous)
    case .next:
      onNavigate(.next)
    case .dismiss:
      onDismiss()
    case .openItem:
      onOpenItem()
      onDismiss()
    }
    return true
  }

  private func physicalPhase(
    for phase: NSEvent.Phase
  ) -> TopSurfaceGesturePhase {
    if phase.contains(.began) {
      return .began
    }
    if phase.contains(.changed) || phase.contains(.stationary) {
      return .changed
    }
    if phase.contains(.ended) {
      return .ended
    }
    if phase.contains(.cancelled) {
      return .cancelled
    }
    return .none
  }

  private func momentumPhase(
    for phase: NSEvent.Phase
  ) -> SurfaceScrollMomentumPhase {
    if phase.contains(.began) {
      return .began
    }
    if phase.contains(.changed) || phase.contains(.stationary) {
      return .changed
    }
    if phase.contains(.ended) || phase.contains(.cancelled) {
      return .ended
    }
    return .none
  }
}
