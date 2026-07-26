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

  private let actionRouter: TopSurfaceActionRouter
  private let eventView: TopSurfaceEventView
  private let hostState: TopSurfaceHostState
  var onPresentedGeometryChanged: () -> Void = {}
  var onPointerInteractionChanged: (Bool) -> Void = { _ in }
  var onAccessibilityInteractionChanged: (Bool) -> Void = { _ in }
  private var keyboardNavigationEnabled = false
  private var keyboardEventMonitor: Any?

  var hostingViewIdentity: ObjectIdentifier {
    ObjectIdentifier(eventView.hostingView)
  }

  var transitionContext: SurfaceTransitionContext {
    hostState.transitionContext
  }

  var liveHostedLayerCount: Int {
    hostState.liveLayerCount
  }

  var areComponentControlsEnabled: Bool {
    hostState.transitionContext.phase == .settled
  }

  var presentedSurfaceFrameInPanel: CGRect {
    eventView.presentedGeometry.frame
  }

  var renderedPresentationStyle: TopSurfacePresentationStyle {
    hostState.snapshot.presentationStyle
  }

  var renderedSurfaceFrameInPanel: CGRect {
    hostState.snapshot.surfaceFrameInPanel
  }

  var renderedContent: TopSurfaceContent {
    guard case .focus(let content) = hostState.snapshot.content else {
      preconditionFailure("The panel is currently rendering media")
    }
    return content
  }

  var renderedMediaPayload: MediaSurfacePayload? {
    guard case .media(let payload) = hostState.snapshot.content else {
      return nil
    }
    return payload
  }

  var renderedCalendarPayload: CalendarSurfacePayload? {
    guard case .calendar(let payload) = hostState.snapshot.content else {
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
    let initialSnapshot = TopSurfaceHostSnapshot(
      content: panelContent,
      presentationStyle: presentationStyle,
      panelSize: contentRect.size,
      surfaceFrameInPanel: resolvedSurfaceFrame
    )
    let hostState = TopSurfaceHostState(initialSnapshot: initialSnapshot)
    let actionRouter = TopSurfaceActionRouter(
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem,
      onMediaAction: onMediaAction,
      areComponentControlsEnabled: {
        [weak hostState] in
        hostState?.transitionContext.phase == .settled
      },
      onAccessibilityNavigationAction: {
        [weak hostState] action in
        hostState?.requestAccessibilityFocus(for: action)
      }
    )
    self.actionRouter = actionRouter
    self.hostState = hostState
    eventView = TopSurfaceEventView(
      frame: CGRect(origin: .zero, size: contentRect.size),
      activeFrame: resolvedSurfaceFrame,
      rootView: AnyView(
        TopSurfaceHostView(
          state: hostState,
          actionRouter: actionRouter
        )
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
    eventView.onNavigate = actionRouter.navigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = actionRouter.openItem
    eventView.updatePresentedGeometry(initialSnapshot.presentedGeometry)
    hostState.onPresentedGeometryChanged = {
      [weak eventView, weak self] geometry in
      eventView?.updatePresentedGeometry(geometry)
      self?.onPresentedGeometryChanged()
    }
    hostState.onAccessibilityInteractionChanged = {
      [weak self] isActive in
      self?.onAccessibilityInteractionChanged(isActive)
    }
    hostState.onTransitionSettled = { [weak self] in
      self?.onPresentedGeometryChanged()
    }
    contentView = eventView
    sharingType = .readOnly
  }

  func update(
    content: TopSurfaceContent,
    presentationStyle: TopSurfacePresentationStyle,
    surfaceFrameInPanel: CGRect,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (SurfaceScrollEvent) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void,
    onDismiss: @escaping () -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void
  ) {
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onDismiss = onDismiss
    actionRouter.update(
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem,
      onMediaAction: { _ in }
    )
    hostState.update(
      snapshot: TopSurfaceHostSnapshot(
        content: .focus(content),
        presentationStyle: presentationStyle,
        panelSize: eventView.bounds.size,
        surfaceFrameInPanel: surfaceFrameInPanel
      ),
      intent: transitionIntent,
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    )
  }

  func update(
    mediaPayload: MediaSurfacePayload,
    presentationStyle: TopSurfacePresentationStyle,
    surfaceFrameInPanel: CGRect,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (SurfaceScrollEvent) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void = { _ in },
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) {
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onDismiss = onDismiss
    actionRouter.update(
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: onNavigate,
      onOpenItem: {},
      onMediaAction: onMediaAction
    )
    hostState.update(
      snapshot: TopSurfaceHostSnapshot(
        content: .media(mediaPayload),
        presentationStyle: presentationStyle,
        panelSize: eventView.bounds.size,
        surfaceFrameInPanel: surfaceFrameInPanel
      ),
      intent: transitionIntent,
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    )
  }

  func update(
    calendarPayload: CalendarSurfacePayload,
    presentationStyle: TopSurfacePresentationStyle,
    surfaceFrameInPanel: CGRect,
    transitionIntent: SurfaceTransitionIntent = .content,
    onHoverChanged: @escaping (Bool) -> Void,
    onScroll: @escaping (SurfaceScrollEvent) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void = {},
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {}
  ) {
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onDismiss = onDismiss
    actionRouter.update(
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: { _ in },
      onOpenItem: {},
      onMediaAction: { _ in }
    )
    hostState.update(
      snapshot: TopSurfaceHostSnapshot(
        content: .calendar(calendarPayload),
        presentationStyle: presentationStyle,
        panelSize: eventView.bounds.size,
        surfaceFrameInPanel: surfaceFrameInPanel
      ),
      intent: transitionIntent,
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    )
  }

  func performActivateSurface() {
    actionRouter.activateSurface()
  }

  func performMediaAction(_ action: MediaSurfaceAction) {
    actionRouter.performMediaAction(action)
  }

  func performSurfaceNavigation(_ intent: SurfaceGestureIntent) {
    actionRouter.navigateSurface(intent)
  }

  func cancelTransitionForLifecycle() {
    hostState.cancelForLifecycle()
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
    switch event.type {
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      onPointerInteractionChanged(true)
    case .leftMouseUp, .rightMouseUp, .otherMouseUp:
      onPointerInteractionChanged(false)
    default:
      break
    }
    if keyboardNavigationEnabled,
      event.type == .keyDown,
      eventView.handleKeyboardEvent(event)
    {
      return
    }
    super.sendEvent(event)
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
    return reconcile(isInside: activeFrame.contains(pointerLocation))
  }

  mutating func reconcile(isInside: Bool) -> Bool? {
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
  private(set) var presentedGeometry: TopSurfacePresentedGeometry

  private var hoverTrackingArea: NSTrackingArea?
  private var hoverRegion: TopSurfaceHoverRegion

  init(
    frame: CGRect,
    activeFrame: CGRect,
    rootView: AnyView
  ) {
    hoverRegion = TopSurfaceHoverRegion(activeFrame: activeFrame)
    presentedGeometry = TopSurfacePresentedGeometry(
      frame: activeFrame,
      presentationStyle: .floatingCapsule,
      level: .compact,
      panelBounds: CGRect(origin: .zero, size: frame.size)
    )
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

  func updatePresentedGeometry(
    _ geometry: TopSurfacePresentedGeometry
  ) {
    presentedGeometry = geometry
    let frame = geometry.frame
    if hoverRegion.activeFrame != frame {
      _ = hoverRegion.updateActiveFrame(
        frame,
        pointerLocation: nil
      )
    }
    reconcileHover(at: currentPointerLocation())
  }

  override func updateTrackingAreas() {
    if let hoverTrackingArea {
      removeTrackingArea(hoverTrackingArea)
    }

    let area = NSTrackingArea(
      rect: .zero,
      options: [
        .mouseEnteredAndExited,
        .mouseMoved,
        .activeAlways,
        .inVisibleRect,
      ],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    hoverTrackingArea = area
    super.updateTrackingAreas()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard presentedGeometry.contains(point) else {
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

  override func mouseMoved(with event: NSEvent) {
    reconcileHover(at: convert(event.locationInWindow, from: nil))
  }

  private func reconcileHover(at point: CGPoint?) {
    guard let point else {
      return
    }
    if let hoverChange = hoverRegion.reconcile(
      isInside: presentedGeometry.containsForHover(
        point,
        wasInside: hoverRegion.isPointerInside
      )
    ) {
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
