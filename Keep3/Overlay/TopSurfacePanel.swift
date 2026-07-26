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
  private var panelContent: PanelContent
  private(set) var renderedPresentationStyle: TopSurfacePresentationStyle
  private(set) var renderedSurfaceFrameInPanel: CGRect
  var onPresentedGeometryChanged: () -> Void = {}
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
    let actionRouter = TopSurfaceActionRouter(
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem,
      onMediaAction: onMediaAction
    )
    let initialSnapshot = TopSurfaceHostSnapshot(
      content: panelContent,
      presentationStyle: presentationStyle,
      panelSize: contentRect.size,
      surfaceFrameInPanel: resolvedSurfaceFrame
    )
    let hostState = TopSurfaceHostState(initialSnapshot: initialSnapshot)
    self.actionRouter = actionRouter
    self.hostState = hostState
    self.panelContent = panelContent
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = resolvedSurfaceFrame
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
    eventView.onNavigate = onNavigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = onOpenItem
    eventView.updatePresentedGeometry(initialSnapshot.presentedGeometry)
    hostState.onPresentedGeometryChanged = {
      [weak eventView, weak self] geometry in
      eventView?.updatePresentedGeometry(geometry)
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
    panelContent = .focus(content)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = onNavigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = onOpenItem
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
        content: panelContent,
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
    panelContent = .media(mediaPayload)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = onNavigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = {}
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
        content: panelContent,
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
    panelContent = .calendar(calendarPayload)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = { _ in }
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = {}
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
        content: panelContent,
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
    if keyboardNavigationEnabled,
      event.type == .keyDown,
      eventView.handleKeyboardEvent(event)
    {
      return
    }
    super.sendEvent(event)
  }
}

enum PanelContent: Equatable {
  case focus(TopSurfaceContent)
  case media(MediaSurfacePayload)
  case calendar(CalendarSurfacePayload)
}

struct TopSurfaceHostSnapshot: Equatable {
  let content: PanelContent
  let presentationStyle: TopSurfacePresentationStyle
  let panelSize: CGSize
  let surfaceFrameInPanel: CGRect

  var layout: TopSurfaceHostedLayout {
    TopSurfaceHostedLayout(
      panelSize: panelSize,
      surfaceFrameInPanel: surfaceFrameInPanel
    )
  }

  var presentation: TopSurfacePresentation {
    switch content {
    case .focus(let focus):
      .focus(
        FocusSurfacePayload(
          visibleItemID: focus.item.id,
          isExpanded: focus.isExpanded,
          level: focus.level,
          revision: focus.presentationRevision,
          expansionReason: .none,
          isHovered: focus.isHovered
        )
      )
    case .media(let media):
      .media(media)
    case .calendar(let calendar):
      .calendar(calendar)
    }
  }

  var isHovered: Bool {
    switch content {
    case .focus(let focus):
      focus.isHovered && focus.level != .expanded
    case .media(let media):
      media.isHovered && media.level != .expanded
    case .calendar(let calendar):
      calendar.isHovered && calendar.level != .expanded
    }
  }

  var level: SurfaceLevel {
    switch content {
    case .focus(let focus):
      focus.level
    case .media(let media):
      media.level
    case .calendar(let calendar):
      calendar.level
    }
  }

  var isQuickPeek: Bool {
    guard case .media(let media) = content else {
      return false
    }
    return media.trackPeek != nil
  }

  var presentedGeometry: TopSurfacePresentedGeometry {
    TopSurfacePresentedGeometry(
      frame: surfaceFrameInPanel,
      presentationStyle: presentationStyle,
      level: level,
      isQuickPeek: isQuickPeek,
      panelBounds: CGRect(origin: .zero, size: panelSize)
    )
  }
}

struct TopSurfacePresentedGeometry: Equatable {
  let frame: CGRect
  let presentationStyle: TopSurfacePresentationStyle
  let level: SurfaceLevel
  let isQuickPeek: Bool
  let panelBounds: CGRect

  init(
    frame: CGRect,
    presentationStyle: TopSurfacePresentationStyle,
    level: SurfaceLevel,
    isQuickPeek: Bool = false,
    panelBounds: CGRect
  ) {
    let clippedFrame = frame.intersection(panelBounds)
    self.frame = clippedFrame.isNull ? .zero : clippedFrame
    self.presentationStyle = presentationStyle
    self.level = level
    self.isQuickPeek = isQuickPeek
    self.panelBounds = panelBounds
  }

  func interpolated(
    to target: TopSurfacePresentedGeometry,
    progress: CGFloat
  ) -> TopSurfacePresentedGeometry {
    let fraction = min(max(progress, 0), 1)
    if fraction == 0 {
      return self
    }
    if fraction == 1 {
      return target
    }
    return TopSurfacePresentedGeometry(
      frame: CGRect(
        x: frame.minX + ((target.frame.minX - frame.minX) * fraction),
        y: frame.minY + ((target.frame.minY - frame.minY) * fraction),
        width: frame.width + ((target.frame.width - frame.width) * fraction),
        height:
          frame.height + ((target.frame.height - frame.height) * fraction)
      ),
      presentationStyle:
        fraction < 0.5 ? presentationStyle : target.presentationStyle,
      level: fraction < 0.5 ? level : target.level,
      isQuickPeek: fraction < 0.5 ? isQuickPeek : target.isQuickPeek,
      panelBounds: target.panelBounds
    )
  }

  func contains(_ pointInPanel: CGPoint) -> Bool {
    guard frame.contains(pointInPanel), !frame.isEmpty else {
      return false
    }
    let pointInShape = CGPoint(
      x: pointInPanel.x - frame.minX,
      y: frame.maxY - pointInPanel.y
    )
    return TopSurfaceShape(
      presentationStyle: presentationStyle,
      isExpanded: level == .expanded,
      isQuickPeek: isQuickPeek
    )
    .path(in: CGRect(origin: .zero, size: frame.size))
    .contains(pointInShape)
  }
}

@MainActor
final class TopSurfaceHostState: ObservableObject {
  private(set) var snapshot: TopSurfaceHostSnapshot
  private(set) var sourceSnapshot: TopSurfaceHostSnapshot?
  private(set) var transitionContext: SurfaceTransitionContext

  private let coordinator: SurfaceTransitionCoordinator
  var onPresentedGeometryChanged: (TopSurfacePresentedGeometry) -> Void = {
    _ in
  }

  init(initialSnapshot: TopSurfaceHostSnapshot) {
    snapshot = initialSnapshot
    coordinator = SurfaceTransitionCoordinator(
      initialTarget: initialSnapshot.presentation
    )
    transitionContext = coordinator.context
  }

  var liveLayerCount: Int {
    sourceSnapshot == nil ? 1 : 2
  }

  func update(
    snapshot newSnapshot: TopSurfaceHostSnapshot,
    intent: SurfaceTransitionIntent,
    reduceMotion: Bool
  ) {
    let previousSnapshot = snapshot
    let previousContext = transitionContext
    let nextContext = coordinator.transition(
      to: newSnapshot.presentation,
      intent: intent,
      reduceMotion: reduceMotion
    )

    objectWillChange.send()
    snapshot = newSnapshot
    transitionContext = nextContext
    if nextContext.phase == .transitioning {
      if previousContext.phase != .transitioning
        || nextContext.source != previousContext.source
      {
        sourceSnapshot = previousSnapshot
      }
    } else {
      sourceSnapshot = nil
    }
  }

  func complete(generation: UInt64) {
    guard coordinator.complete(generation: generation) else {
      return
    }
    objectWillChange.send()
    transitionContext = coordinator.context
    sourceSnapshot = nil
  }

  func cancelForLifecycle() {
    objectWillChange.send()
    transitionContext = coordinator.cancelForLifecycle()
    sourceSnapshot = nil
  }

  func reportPresentedGeometry(
    _ geometry: TopSurfacePresentedGeometry,
    generation: UInt64
  ) {
    guard generation == transitionContext.generation else {
      return
    }
    onPresentedGeometryChanged(geometry)
  }
}

@MainActor
final class TopSurfaceActionRouter {
  private var onActivateSurface: () -> Void
  private var onRequestKeyboardNavigation: () -> Void
  private var onSurfaceNavigation: (SurfaceGestureIntent) -> Void
  private var onNavigate: (TopSurfaceBrowseDirection) -> Void
  private var onOpenItem: () -> Void
  private var onMediaAction: (MediaSurfaceAction) -> Void

  init(
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void,
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) {
    self.onActivateSurface = onActivateSurface
    self.onRequestKeyboardNavigation = onRequestKeyboardNavigation
    self.onSurfaceNavigation = onSurfaceNavigation
    self.onNavigate = onNavigate
    self.onOpenItem = onOpenItem
    self.onMediaAction = onMediaAction
  }

  func update(
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void,
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) {
    self.onActivateSurface = onActivateSurface
    self.onRequestKeyboardNavigation = onRequestKeyboardNavigation
    self.onSurfaceNavigation = onSurfaceNavigation
    self.onNavigate = onNavigate
    self.onOpenItem = onOpenItem
    self.onMediaAction = onMediaAction
  }

  func activateSurface() {
    onActivateSurface()
  }

  func requestKeyboardNavigation() {
    onRequestKeyboardNavigation()
  }

  func navigateSurface(_ intent: SurfaceGestureIntent) {
    onSurfaceNavigation(intent)
  }

  func navigate(_ direction: TopSurfaceBrowseDirection) {
    onNavigate(direction)
  }

  func openItem() {
    onOpenItem()
  }

  func performMediaAction(_ action: MediaSurfaceAction) {
    onMediaAction(action)
  }
}

private struct TopSurfaceHostView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @ObservedObject var state: TopSurfaceHostState
  let actionRouter: TopSurfaceActionRouter

  @State private var presentedLayout: TopSurfaceHostedLayout
  @State private var handoffPhase: CGFloat = 0

  init(
    state: TopSurfaceHostState,
    actionRouter: TopSurfaceActionRouter
  ) {
    self.state = state
    self.actionRouter = actionRouter
    _presentedLayout = State(initialValue: state.snapshot.layout)
  }

  var body: some View {
    TopSurfaceRootView(
      layout: presentedLayout,
      animatesSurfaceFrame: false,
      isHovered: state.snapshot.isHovered,
      content: ZStack {
        if let source = state.sourceSnapshot {
          hostedContent(
            source,
            surfaceSize: source.surfaceFrameInPanel.size
          )
          .opacity(1 - targetProgress)
          .offset(x: outgoingOffset)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }

        hostedContent(
          state.snapshot,
          surfaceSize: state.snapshot.surfaceFrameInPanel.size
        )
        .opacity(state.sourceSnapshot == nil ? 1 : targetProgress)
        .offset(x: incomingOffset)
        .allowsHitTesting(state.transitionContext.phase == .settled)
        .accessibilityHidden(state.transitionContext.phase != .settled)
      }
    )
    .modifier(
      TopSurfacePresentedGeometryReporter(
        geometry: TopSurfacePresentedGeometry(
          frame: presentedLayout.surfaceFrameInPanel,
          presentationStyle: state.snapshot.presentationStyle,
          level: state.snapshot.level,
          isQuickPeek: state.snapshot.isQuickPeek,
          panelBounds: CGRect(
            origin: .zero,
            size: presentedLayout.panelSize
          )
        ),
        generation: state.transitionContext.generation
      )
    )
    .onPreferenceChange(TopSurfacePresentedGeometryPreferenceKey.self) {
      report in
      guard let report else {
        return
      }
      state.reportPresentedGeometry(
        report.geometry,
        generation: report.generation
      )
    }
    .onChange(of: state.transitionContext.generation) { _, generation in
      beginTransition(generation: generation)
    }
  }

  private var targetProgress: CGFloat {
    state.transitionContext.generation.isMultiple(of: 2)
      ? 1 - handoffPhase : handoffPhase
  }

  private var incomingOffset: CGFloat {
    effectiveDirectionalOffset * (1 - targetProgress)
  }

  private var outgoingOffset: CGFloat {
    -effectiveDirectionalOffset * targetProgress
  }

  private var usesCrossfade: Bool {
    state.transitionContext.motion.motionPolicy == .crossfade
      || reduceMotion
  }

  private var effectiveDirectionalOffset: CGFloat {
    usesCrossfade
      ? 0
      : CGFloat(state.transitionContext.motion.directionalContentOffset)
  }

  @ViewBuilder
  private func hostedContent(
    _ snapshot: TopSurfaceHostSnapshot,
    surfaceSize: CGSize
  ) -> some View {
    switch snapshot.content {
    case .focus(let focus):
      TopSurfaceView(
        content: focus,
        presentationStyle: snapshot.presentationStyle,
        surfaceSize: surfaceSize,
        onActivateSurface: actionRouter.activateSurface,
        onRequestKeyboardNavigation:
          actionRouter.requestKeyboardNavigation,
        onSurfaceNavigation: actionRouter.navigateSurface,
        onNavigate: actionRouter.navigate,
        onOpenItem: actionRouter.openItem
      )
    case .media(let media):
      MediaSurfaceView(
        payload: media,
        presentationStyle: snapshot.presentationStyle,
        surfaceSize: surfaceSize,
        onAction: actionRouter.performMediaAction,
        onActivateSurface: actionRouter.activateSurface,
        onRequestKeyboardNavigation:
          actionRouter.requestKeyboardNavigation,
        onSurfaceNavigation: actionRouter.navigateSurface
      )
    case .calendar(let calendar):
      CalendarSurfaceView(
        payload: calendar,
        presentationStyle: snapshot.presentationStyle,
        surfaceSize: surfaceSize,
        onActivateSurface: actionRouter.activateSurface,
        onRequestKeyboardNavigation:
          actionRouter.requestKeyboardNavigation,
        onSurfaceNavigation: actionRouter.navigateSurface
      )
    }
  }

  private func beginTransition(generation: UInt64) {
    let context = state.transitionContext
    guard context.phase == .transitioning else {
      presentedLayout = state.snapshot.layout
      return
    }

    if usesCrossfade {
      var layoutTransaction = Transaction()
      layoutTransaction.disablesAnimations = true
      withTransaction(layoutTransaction) {
        presentedLayout = state.snapshot.layout
      }
    }

    let animation = Animation.timingCurve(
      0.2,
      0.8,
      0.2,
      1,
      duration: usesCrossfade ? 0.12 : context.motion.duration
    )
    withAnimation(
      animation,
      completionCriteria: .logicallyComplete
    ) {
      if !usesCrossfade {
        presentedLayout = state.snapshot.layout
      }
      handoffPhase =
        generation.isMultiple(of: 2) ? 0 : 1
    } completion: {
      Task { @MainActor [weak state] in
        state?.complete(generation: generation)
      }
    }
  }
}

private struct TopSurfacePresentedGeometryReport: Equatable {
  let geometry: TopSurfacePresentedGeometry
  let generation: UInt64
}

private struct TopSurfacePresentedGeometryPreferenceKey: PreferenceKey {
  static let defaultValue: TopSurfacePresentedGeometryReport? = nil

  static func reduce(
    value: inout TopSurfacePresentedGeometryReport?,
    nextValue: () -> TopSurfacePresentedGeometryReport?
  ) {
    value = nextValue() ?? value
  }
}

private struct TopSurfacePresentedGeometryReporter: AnimatableModifier {
  var geometry: TopSurfacePresentedGeometry
  let generation: UInt64

  nonisolated var animatableData:
    AnimatablePair<
      AnimatablePair<CGFloat, CGFloat>,
      AnimatablePair<CGFloat, CGFloat>
    >
  {
    get {
      AnimatablePair(
        AnimatablePair(geometry.frame.origin.x, geometry.frame.origin.y),
        AnimatablePair(geometry.frame.width, geometry.frame.height)
      )
    }
    set {
      geometry = TopSurfacePresentedGeometry(
        frame: CGRect(
          x: newValue.first.first,
          y: newValue.first.second,
          width: newValue.second.first,
          height: newValue.second.second
        ),
        presentationStyle: geometry.presentationStyle,
        level: geometry.level,
        isQuickPeek: geometry.isQuickPeek,
        panelBounds: geometry.panelBounds
      )
    }
  }

  func body(content: Content) -> some View {
    content.preference(
      key: TopSurfacePresentedGeometryPreferenceKey.self,
      value: TopSurfacePresentedGeometryReport(
        geometry: geometry,
        generation: generation
      )
    )
  }
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
  let isHovered: Bool
  let content: Content

  var body: some View {
    let hoverEffect = TopSurfaceHoverEffect(isActive: isHovered)
    ZStack(alignment: .topLeading) {
      content
        .frame(
          width: layout.surfaceFrameInPanel.width,
          height: layout.surfaceFrameInPanel.height
        )
        .position(layout.centerInSwiftUICoordinates)
        .scaleEffect(
          x: hoverEffect.scaleX,
          y: hoverEffect.scaleY,
          anchor: .top
        )
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
    .animation(
      !reduceMotion ? .easeOut(duration: 0.16) : nil,
      value: isHovered
    )
  }
}

struct TopSurfaceHoverEffect: Equatable {
  let scaleX: CGFloat
  let scaleY: CGFloat

  init(isActive: Bool) {
    scaleX = isActive ? 1.02 : 1
    scaleY = isActive ? 1.05 : 1
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

  func updateActiveFrame(_ frame: CGRect) {
    updatePresentedGeometry(
      TopSurfacePresentedGeometry(
        frame: frame,
        presentationStyle: presentedGeometry.presentationStyle,
        level: presentedGeometry.level,
        isQuickPeek: presentedGeometry.isQuickPeek,
        panelBounds: presentedGeometry.panelBounds
      )
    )
  }

  func updatePresentedGeometry(
    _ geometry: TopSurfacePresentedGeometry
  ) {
    presentedGeometry = geometry
    let frame = geometry.frame
    guard hoverRegion.activeFrame != frame else {
      reconcileHover(at: currentPointerLocation())
      return
    }
    _ = hoverRegion.updateActiveFrame(
      frame,
      pointerLocation: nil
    )
    updateTrackingAreas()
    reconcileHover(at: currentPointerLocation())
  }

  override func updateTrackingAreas() {
    if let hoverTrackingArea {
      removeTrackingArea(hoverTrackingArea)
    }

    let area = NSTrackingArea(
      rect: hoverRegion.activeFrame,
      options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
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
      isInside: presentedGeometry.contains(point)
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
