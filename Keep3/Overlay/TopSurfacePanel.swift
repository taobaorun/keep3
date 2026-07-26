import AppKit
import SwiftUI

enum TopSurfaceKeyboardCommand: Equatable, Sendable {
  case previous
  case next
  case surfaceUp
  case surfaceDown
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
    case 126:
      self = .surfaceUp
    case 125:
      self = .surfaceDown
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

  var renderedCalendarPayload: CalendarSurfacePayload? {
    guard case .calendar(let payload) = panelContent else {
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
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
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
      onSurfaceNavigation: onSurfaceNavigation,
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
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void = { _ in },
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
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: {},
      onMediaAction: onMediaAction
    )
  }

  convenience init(
    contentRect: CGRect,
    surfaceFrameInPanel: CGRect? = nil,
    calendarPayload: CalendarSurfacePayload,
    presentationStyle: TopSurfacePresentationStyle = .floatingCapsule,
    onHoverChanged: @escaping (Bool) -> Void = { _ in },
    onScroll: @escaping (SurfaceScrollEvent) -> Void = { _ in },
    onActivateSurface: @escaping () -> Void = {},
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {}
  ) {
    self.init(
      contentRect: contentRect,
      surfaceFrameInPanel: surfaceFrameInPanel,
      panelContent: .calendar(calendarPayload),
      presentationStyle: presentationStyle,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onDismiss: onDismiss,
      onNavigate: { _ in },
      onOpenItem: {},
      onMediaAction: { _ in }
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
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void,
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
        panelSize: contentRect.size,
        surfaceFrameInPanel: resolvedSurfaceFrame,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onSurfaceNavigation: onSurfaceNavigation,
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
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void,
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
      panelSize: eventView.bounds.size,
      surfaceFrameInPanel: surfaceFrameInPanel,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem,
      onMediaAction: { _ in }
    )
  }

  func update(
    mediaPayload: MediaSurfacePayload,
    presentationStyle: TopSurfacePresentationStyle,
    surfaceFrameInPanel: CGRect,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (SurfaceScrollEvent) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void = { _ in },
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) {
    panelContent = .media(mediaPayload)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = onNavigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = {}
    eventView.updateActiveFrame(surfaceFrameInPanel)
    eventView.hostingView.rootView = Self.rootView(
      for: panelContent,
      presentationStyle: presentationStyle,
      panelSize: eventView.bounds.size,
      surfaceFrameInPanel: surfaceFrameInPanel,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: onNavigate,
      onOpenItem: {},
      onMediaAction: onMediaAction
    )
  }

  func update(
    calendarPayload: CalendarSurfacePayload,
    presentationStyle: TopSurfacePresentationStyle,
    surfaceFrameInPanel: CGRect,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (SurfaceScrollEvent) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {}
  ) {
    panelContent = .calendar(calendarPayload)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = { _ in }
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = {}
    eventView.updateActiveFrame(surfaceFrameInPanel)
    eventView.hostingView.rootView = Self.rootView(
      for: panelContent,
      presentationStyle: presentationStyle,
      panelSize: eventView.bounds.size,
      surfaceFrameInPanel: surfaceFrameInPanel,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: { _ in },
      onOpenItem: {},
      onMediaAction: { _ in }
    )
  }

  private static func rootView(
    for content: PanelContent,
    presentationStyle: TopSurfacePresentationStyle,
    panelSize: CGSize,
    surfaceFrameInPanel: CGRect,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void,
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) -> AnyView {
    let surfaceSize = surfaceFrameInPanel.size
    let layout = TopSurfaceHostedLayout(
      panelSize: panelSize,
      surfaceFrameInPanel: surfaceFrameInPanel
    )

    switch content {
    case .focus(let focus):
      return AnyView(
        TopSurfaceRootView(
          layout: layout,
          animatesSurfaceFrame: false,
          content: TopSurfaceView(
            content: focus,
            presentationStyle: presentationStyle,
            surfaceSize: surfaceSize,
            onActivateSurface: onActivateSurface,
            onRequestKeyboardNavigation: onRequestKeyboardNavigation,
            onSurfaceNavigation: onSurfaceNavigation,
            onNavigate: onNavigate,
            onOpenItem: onOpenItem
          )
        )
      )
    case .media(let media):
      return AnyView(
        TopSurfaceRootView(
          layout: layout,
          animatesSurfaceFrame: true,
          content: MediaSurfaceView(
            payload: media,
            presentationStyle: presentationStyle,
            surfaceSize: surfaceSize,
            onAction: onMediaAction,
            onActivateSurface: onActivateSurface,
            onRequestKeyboardNavigation: onRequestKeyboardNavigation,
            onSurfaceNavigation: onSurfaceNavigation
          )
        )
      )
    case .calendar(let calendar):
      return AnyView(
        TopSurfaceRootView(
          layout: layout,
          animatesSurfaceFrame: false,
          content: CalendarSurfaceView(
            payload: calendar,
            presentationStyle: presentationStyle,
            surfaceSize: surfaceSize,
            onActivateSurface: onActivateSurface,
            onRequestKeyboardNavigation: onRequestKeyboardNavigation,
            onSurfaceNavigation: onSurfaceNavigation
          )
        )
      )
    }
  }

  func setKeyboardNavigationEnabled(
    _ isEnabled: Bool,
    activateApplication: Bool = true
  ) {
    guard keyboardNavigationEnabled != isEnabled else {
      return
    }
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
  case calendar(CalendarSurfacePayload)
}

struct TopSurfaceHostedLayout: Equatable {
  let panelSize: CGSize
  let surfaceFrameInPanel: CGRect

  var centerInSwiftUICoordinates: CGPoint {
    CGPoint(
      x: surfaceFrameInPanel.midX,
      y: panelSize.height - surfaceFrameInPanel.midY
    )
  }
}

private struct TopSurfaceRootView<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let layout: TopSurfaceHostedLayout
  let animatesSurfaceFrame: Bool
  let content: Content

  var body: some View {
    ZStack(alignment: .topLeading) {
      content
        .frame(
          width: layout.surfaceFrameInPanel.width,
          height: layout.surfaceFrameInPanel.height
        )
        .position(layout.centerInSwiftUICoordinates)
    }
    .frame(
      width: layout.panelSize.width,
      height: layout.panelSize.height,
      alignment: .topLeading
    )
    .animation(
      animatesSurfaceFrame && !reduceMotion
        ? .spring(response: 0.4, dampingFraction: 0.68)
        : nil,
      value: layout.surfaceFrameInPanel
    )
  }
}

struct TopSurfaceHoverRegion: Equatable {
  private(set) var activeFrame: CGRect
  private(set) var isPointerInside = false

  init(activeFrame: CGRect) {
    self.activeFrame = activeFrame
  }

  mutating func updateActiveFrame(
    _ frame: CGRect,
    pointerLocation: CGPoint?
  ) -> Bool? {
    activeFrame = frame
    return reconcile(pointerLocation: pointerLocation)
  }

  mutating func reconcile(pointerLocation: CGPoint?) -> Bool? {
    guard let pointerLocation else {
      return nil
    }
    let isInside = activeFrame.contains(pointerLocation)
    guard isPointerInside != isInside else {
      return nil
    }
    isPointerInside = isInside
    return isInside
  }
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
  private var hoverRegion: TopSurfaceHoverRegion

  init(
    frame: CGRect,
    activeFrame: CGRect,
    rootView: AnyView
  ) {
    hoverRegion = TopSurfaceHoverRegion(activeFrame: activeFrame)
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
    guard hoverRegion.activeFrame != frame else {
      return
    }
    let hoverChange = hoverRegion.updateActiveFrame(
      frame,
      pointerLocation: currentPointerLocation()
    )
    updateTrackingAreas()
    if let hoverChange {
      onHoverChanged(hoverChange)
    }
  }

  override func updateTrackingAreas() {
    if let hoverTrackingArea {
      removeTrackingArea(hoverTrackingArea)
    }

    let area = NSTrackingArea(
      rect: hoverRegion.activeFrame,
      options: [.mouseEnteredAndExited, .activeAlways],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    hoverTrackingArea = area
    super.updateTrackingAreas()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard hoverRegion.activeFrame.contains(point) else {
      return nil
    }
    return super.hitTest(point)
  }

  override func mouseEntered(with event: NSEvent) {
    reconcileHover(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseExited(with event: NSEvent) {
    reconcileHover(at: convert(event.locationInWindow, from: nil))
  }

  private func reconcileHover(at point: CGPoint) {
    if let hoverChange = hoverRegion.reconcile(pointerLocation: point) {
      onHoverChanged(hoverChange)
    }
  }

  private func currentPointerLocation() -> CGPoint? {
    guard let window else {
      return nil
    }
    return convert(window.mouseLocationOutsideOfEventStream, from: nil)
  }

  override func scrollWheel(with event: NSEvent) {
    let locationInScreen = window?.convertPoint(
      toScreen: event.locationInWindow
    )
    onScroll(
      SurfaceScrollEvent(
        deltaX: event.scrollingDeltaX,
        deltaY: event.scrollingDeltaY,
        isPrecise: event.hasPreciseScrollingDeltas,
        physicalPhase: physicalPhase(for: event.phase),
        momentumPhase: momentumPhase(for: event.momentumPhase),
        locationInScreen: locationInScreen
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
    case .surfaceUp:
      emitVerticalKeyboardGesture(deltaY: -30)
    case .surfaceDown:
      emitVerticalKeyboardGesture(deltaY: 30)
    case .dismiss:
      onDismiss()
    case .openItem:
      onOpenItem()
      onDismiss()
    }
    return true
  }

  private func emitVerticalKeyboardGesture(deltaY: CGFloat) {
    onScroll(
      SurfaceScrollEvent(
        deltaX: 0,
        deltaY: deltaY,
        isPrecise: true,
        physicalPhase: .began,
        momentumPhase: .none
      )
    )
    onScroll(
      SurfaceScrollEvent(
        deltaX: 0,
        deltaY: 0,
        isPrecise: true,
        physicalPhase: .ended,
        momentumPhase: .none
      )
    )
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
