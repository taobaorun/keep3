import AppKit
import SwiftUI

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

struct SurfaceRendererContext: Equatable, Sendable {
  let intent: SurfaceTransitionIntent
  let motion: SignatureSurfaceTransition
  let accessibilityFocusRequest: SurfaceAccessibilityFocusRequest?

  static let initial = SurfaceRendererContext(
    intent: .initial,
    motion: SignatureSurfaceTransition.resolve(
      intent: .initial,
      reduceMotion: false,
      reduceTransparency: false,
      increaseContrast: false,
      differentiateWithoutColor: false
    ),
    accessibilityFocusRequest: nil
  )

  init(
    context: SurfaceTransitionContext,
    accessibilityFocusRequest: SurfaceAccessibilityFocusRequest?
  ) {
    intent = SurfaceTransitionIntent(
      trigger: context.trigger,
      direction: context.direction
    )
    motion = context.motion
    self.accessibilityFocusRequest = accessibilityFocusRequest
  }

  private init(
    intent: SurfaceTransitionIntent,
    motion: SignatureSurfaceTransition,
    accessibilityFocusRequest: SurfaceAccessibilityFocusRequest?
  ) {
    self.intent = intent
    self.motion = motion
    self.accessibilityFocusRequest = accessibilityFocusRequest
  }
}

struct TopSurfacePresentedGeometry: Equatable {
  private static let floatingExitSlop: CGFloat = 8

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
    let fraction = progress.clamped(to: 0...1)
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

  var hoverTrackingFrame: CGRect {
    let proposedFrame: CGRect
    switch presentationStyle {
    case .floatingCapsule:
      proposedFrame = frame.insetBy(
        dx: -Self.floatingExitSlop,
        dy: -Self.floatingExitSlop
      )
    case .notchAttached:
      proposedFrame = CGRect(
        x: frame.minX,
        y: frame.minY,
        width: frame.width,
        height: max(0, panelBounds.maxY - frame.minY)
      )
    }
    let clippedFrame = proposedFrame.intersection(panelBounds)
    return clippedFrame.isNull ? .zero : clippedFrame
  }

  func containsForHover(
    _ pointInPanel: CGPoint,
    wasInside: Bool
  ) -> Bool {
    if contains(pointInPanel) {
      return true
    }
    guard wasInside, hoverTrackingFrame.contains(pointInPanel) else {
      return false
    }
    switch presentationStyle {
    case .notchAttached:
      return true
    case .floatingCapsule:
      let pointInShape = CGPoint(
        x: pointInPanel.x - frame.minX,
        y: frame.maxY - pointInPanel.y
      )
      let path = TopSurfaceShape(
        presentationStyle: presentationStyle,
        isExpanded: level == .expanded,
        isQuickPeek: isQuickPeek
      )
      .path(in: CGRect(origin: .zero, size: frame.size))
      return path.strokedPath(
        StrokeStyle(lineWidth: Self.floatingExitSlop * 2)
      )
      .contains(pointInShape)
    }
  }
}

@MainActor
final class TopSurfaceHostState: ObservableObject {
  private(set) var snapshot: TopSurfaceHostSnapshot
  private(set) var sourceSnapshot: TopSurfaceHostSnapshot?
  private(set) var transitionContext: SurfaceTransitionContext
  private(set) var shellGeneration: UInt64 = 0
  private(set) var handoffStartGeneration: UInt64 = 0
  private(set) var layoutOnlyGeneration: UInt64?
  private(set) var visualMotion: SignatureSurfaceTransition
  private(set) var accessibilityFocusRequest: SurfaceAccessibilityFocusRequest?

  private let coordinator: SurfaceTransitionCoordinator
  private var shellCompletionGeneration: UInt64 = 0
  private var pendingAccessibilityAction: SurfaceAccessibilityNavigationAction?
  private var isAccessibilityInteractionActive = false
  private var accessibilityFocusGeneration: UInt64 = 0
  var onPresentedGeometryChanged: (TopSurfacePresentedGeometry) -> Void = {
    _ in
  }
  var onAccessibilityInteractionChanged: (Bool) -> Void = { _ in }
  var onTransitionSettled: () -> Void = {}

  init(initialSnapshot: TopSurfaceHostSnapshot) {
    snapshot = initialSnapshot
    coordinator = SurfaceTransitionCoordinator(
      initialTarget: initialSnapshot.presentation
    )
    transitionContext = coordinator.context
    visualMotion = coordinator.context.motion
  }

  var liveLayerCount: Int {
    sourceSnapshot == nil ? 1 : 2
  }

  var rendererContext: SurfaceRendererContext {
    SurfaceRendererContext(
      context: transitionContext,
      accessibilityFocusRequest: accessibilityFocusRequest
    )
  }

  func update(
    snapshot newSnapshot: TopSurfaceHostSnapshot,
    intent: SurfaceTransitionIntent,
    reduceMotion: Bool
  ) {
    guard
      newSnapshot != snapshot
        || transitionContext.target != newSnapshot.presentation
    else {
      return
    }
    let previousSnapshot = snapshot
    let previousContext = transitionContext
    let layoutChanged = previousSnapshot.layout != newSnapshot.layout
    let nextContext = coordinator.transition(
      to: newSnapshot.presentation,
      intent: intent,
      reduceMotion: reduceMotion
    )
    let isPureContentUpdate =
      nextContext.phase == .transitioning
      && nextContext.trigger == .content
    let continuesCurrentShellTransition =
      previousContext.phase == .transitioning
      && nextContext.phase == .transitioning
      && nextContext.source == previousContext.source
      && nextContext.trigger == previousContext.trigger
      && nextContext.direction == previousContext.direction

    objectWillChange.send()
    snapshot = newSnapshot
    if isPureContentUpdate {
      _ = coordinator.complete(generation: nextContext.generation)
      transitionContext = coordinator.context
      sourceSnapshot = nil
      if layoutChanged {
        shellGeneration &+= 1
        layoutOnlyGeneration = shellGeneration
        visualMotion = nextContext.motion
      }
      settlePendingAccessibilityFocus()
    } else if nextContext.phase == .transitioning {
      transitionContext = nextContext
      shellCompletionGeneration = nextContext.generation
      if !continuesCurrentShellTransition || layoutChanged {
        shellGeneration &+= 1
        layoutOnlyGeneration = nil
        visualMotion = nextContext.motion
        if previousContext.phase != .transitioning {
          handoffStartGeneration = shellGeneration
        }
      }
      if previousContext.phase != .transitioning {
        sourceSnapshot = previousSnapshot
      }
    } else {
      transitionContext = nextContext
      sourceSnapshot = nil
      layoutOnlyGeneration = nil
    }
  }

  func complete(shellGeneration: UInt64) {
    guard self.shellGeneration == shellGeneration,
      coordinator.complete(generation: shellCompletionGeneration)
    else {
      return
    }
    objectWillChange.send()
    transitionContext = coordinator.context
    sourceSnapshot = nil
    settlePendingAccessibilityFocus()
    onTransitionSettled()
  }

  func cancelForLifecycle() {
    objectWillChange.send()
    transitionContext = coordinator.cancelForLifecycle()
    sourceSnapshot = nil
    pendingAccessibilityAction = nil
    accessibilityFocusRequest = nil
    endAccessibilityInteraction()
  }

  func requestAccessibilityFocus(
    for action: SurfaceAccessibilityNavigationAction
  ) {
    objectWillChange.send()
    pendingAccessibilityAction = action
    if !isAccessibilityInteractionActive {
      isAccessibilityInteractionActive = true
      onAccessibilityInteractionChanged(true)
    }
    Task { @MainActor [weak self] in
      guard let self, self.transitionContext.phase == .settled else {
        return
      }
      self.objectWillChange.send()
      self.settlePendingAccessibilityFocus()
    }
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

  private func settlePendingAccessibilityFocus() {
    guard transitionContext.phase == .settled,
      let action = pendingAccessibilityAction
    else {
      return
    }
    pendingAccessibilityAction = nil
    if let requested = action.focusDestination,
      let destination = SurfaceAccessibilityFocusResolver.resolve(
        requested: requested,
        phase: transitionContext.phase,
        targetComponent: transitionContext.target.componentID,
        targetLevel: transitionContext.target.level
      )
    {
      accessibilityFocusGeneration &+= 1
      accessibilityFocusRequest = SurfaceAccessibilityFocusRequest(
        generation: accessibilityFocusGeneration,
        destination: destination,
        announcement: action.announcement
      )
    }
    endAccessibilityInteraction()
  }

  private func endAccessibilityInteraction() {
    guard isAccessibilityInteractionActive else {
      return
    }
    isAccessibilityInteractionActive = false
    onAccessibilityInteractionChanged(false)
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
  private let areComponentControlsEnabled: () -> Bool
  private let onAccessibilityNavigationAction: (SurfaceAccessibilityNavigationAction) -> Void

  init(
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void,
    onMediaAction: @escaping (MediaSurfaceAction) -> Void,
    areComponentControlsEnabled: @escaping () -> Bool = { true },
    onAccessibilityNavigationAction: @escaping (
      SurfaceAccessibilityNavigationAction
    ) -> Void
  ) {
    self.onActivateSurface = onActivateSurface
    self.onRequestKeyboardNavigation = onRequestKeyboardNavigation
    self.onSurfaceNavigation = onSurfaceNavigation
    self.onNavigate = onNavigate
    self.onOpenItem = onOpenItem
    self.onMediaAction = onMediaAction
    self.areComponentControlsEnabled = areComponentControlsEnabled
    self.onAccessibilityNavigationAction =
      onAccessibilityNavigationAction
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
    guard areComponentControlsEnabled() else {
      return
    }
    onNavigate(direction)
  }

  func openItem() {
    guard areComponentControlsEnabled() else {
      return
    }
    onOpenItem()
  }

  func performMediaAction(_ action: MediaSurfaceAction) {
    guard areComponentControlsEnabled() else {
      return
    }
    onMediaAction(action)
  }

  func handleAccessibilityNavigationAction(
    _ action: SurfaceAccessibilityNavigationAction
  ) {
    onAccessibilityNavigationAction(action)
  }
}

struct TopSurfaceHostView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private
    var reduceTransparency

  @ObservedObject var state: TopSurfaceHostState
  let actionRouter: TopSurfaceActionRouter

  @State private var presentedLayout: TopSurfaceHostedLayout
  @State private var handoffPhase: CGFloat = 0
  @State private var activeVisualGeneration: UInt64
  @AccessibilityFocusState private
    var isSurfaceContainerAccessibilityFocused: Bool

  init(
    state: TopSurfaceHostState,
    actionRouter: TopSurfaceActionRouter
  ) {
    self.state = state
    self.actionRouter = actionRouter
    _presentedLayout = State(initialValue: state.snapshot.layout)
    _activeVisualGeneration = State(initialValue: state.shellGeneration)
  }

  var body: some View {
    TopSurfaceRootView(
      layout: presentedLayout,
      animatesSurfaceFrame: false,
      isHovered: state.snapshot.isHovered,
      content: shellContent
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
    .onChange(of: state.shellGeneration) { _, generation in
      beginTransition(shellGeneration: generation)
    }
    .onChange(of: state.accessibilityFocusRequest) { _, request in
      handleAccessibilityFocusRequest(request)
    }
    .accessibilityFocused($isSurfaceContainerAccessibilityFocused)
  }

  private var targetProgress: CGFloat {
    if state.handoffStartGeneration == state.shellGeneration,
      activeVisualGeneration != state.shellGeneration
    {
      return 0
    }
    return handoffPhase
  }

  private var incomingOffset: CGFloat {
    effectiveDirectionalOffset * (1 - targetProgress)
  }

  private var outgoingOffset: CGFloat {
    -effectiveDirectionalOffset * targetProgress
  }

  private var usesCrossfade: Bool {
    state.visualMotion.motionPolicy == .crossfade
      || reduceMotion
  }

  private var effectiveDirectionalOffset: CGFloat {
    usesCrossfade
      ? 0
      : CGFloat(state.visualMotion.directionalContentOffset)
  }

  private var shellContent: some View {
    ZStack {
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
    .background {
      ZStack {
        Color.black.opacity(shellBackgroundOpacity(for: state.snapshot))
        if let source = state.sourceSnapshot {
          shellDecoration(for: source)
            .opacity(1 - targetProgress)
        }
        shellDecoration(for: state.snapshot)
          .opacity(state.sourceSnapshot == nil ? 1 : targetProgress)
      }
    }
    .mask {
      shellShape
        .fill(.white)
        .animation(shellShapeAnimation, value: state.shellGeneration)
    }
    .overlay(alignment: .top) {
      if case .notchAttached = state.snapshot.presentationStyle {
        Rectangle()
          .fill(.black)
          .frame(height: 1)
      }
    }
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
        rendererContext: state.rendererContext,
        onActivateSurface: actionRouter.activateSurface,
        onRequestKeyboardNavigation:
          actionRouter.requestKeyboardNavigation,
        onSurfaceNavigation: actionRouter.navigateSurface,
        onNavigate: actionRouter.navigate,
        onOpenItem: actionRouter.openItem,
        onAccessibilityNavigationAction:
          actionRouter.handleAccessibilityNavigationAction
      )
    case .media(let media):
      MediaSurfaceView(
        payload: media,
        presentationStyle: snapshot.presentationStyle,
        surfaceSize: surfaceSize,
        rendererContext: state.rendererContext,
        rendersOwnShell: false,
        onAction: actionRouter.performMediaAction,
        onActivateSurface: actionRouter.activateSurface,
        onRequestKeyboardNavigation:
          actionRouter.requestKeyboardNavigation,
        onSurfaceNavigation: actionRouter.navigateSurface,
        onAccessibilityNavigationAction:
          actionRouter.handleAccessibilityNavigationAction
      )
    case .calendar(let calendar):
      CalendarSurfaceView(
        payload: calendar,
        presentationStyle: snapshot.presentationStyle,
        surfaceSize: surfaceSize,
        rendererContext: state.rendererContext,
        rendersOwnShell: false,
        onActivateSurface: actionRouter.activateSurface,
        onRequestKeyboardNavigation:
          actionRouter.requestKeyboardNavigation,
        onSurfaceNavigation: actionRouter.navigateSurface,
        onAccessibilityNavigationAction:
          actionRouter.handleAccessibilityNavigationAction
      )
    }
  }

  private var shellShape: TopSurfaceShape {
    TopSurfaceShape(
      presentationStyle: state.snapshot.presentationStyle,
      isExpanded: state.snapshot.level == .expanded,
      isQuickPeek: state.snapshot.isQuickPeek
    )
  }

  private var shellShapeAnimation: Animation? {
    guard state.transitionContext.motion.animatesShape, !reduceMotion else {
      return nil
    }
    return .timingCurve(
      0.2,
      0.8,
      0.2,
      1,
      duration: state.visualMotion.duration
    )
  }

  private func shellBackgroundOpacity(
    for snapshot: TopSurfaceHostSnapshot
  ) -> Double {
    if case .notchAttached = snapshot.presentationStyle {
      return 1
    }
    guard !reduceTransparency else {
      return 1
    }
    return switch snapshot.content {
    case .focus(let focus):
      focus.appearance.backgroundOpacity
    case .media(let media):
      media.appearance.backgroundOpacity
    case .calendar:
      0.96
    }
  }

  @ViewBuilder
  private func shellDecoration(
    for snapshot: TopSurfaceHostSnapshot
  ) -> some View {
    if case .media(let payload) = snapshot.content,
      case .floatingCapsule = snapshot.presentationStyle
    {
      let presentation = MediaSurfacePresentation(payload: payload)
      if payload.appearance.artworkTreatment == .gradient {
        LinearGradient(
          colors: [.purple.opacity(0.42), .blue.opacity(0.2), .clear],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      } else if let artwork =
        MediaArtworkDecoder.resolve(presentation.artworkData).image
      {
        Image(decorative: artwork, scale: 1)
          .resizable()
          .scaledToFill()
          .grayscale(
            payload.appearance.artworkTreatment == .monochrome ? 1 : 0
          )
          .blur(radius: 28)
          .opacity(reduceTransparency ? 0 : 0.28)
      }
      LinearGradient(
        colors: [.black.opacity(0.06), .black.opacity(0.58)],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }

  private func beginTransition(shellGeneration: UInt64) {
    let context = state.transitionContext
    let duration =
      usesCrossfade ? 0.12 : state.visualMotion.duration
    let animation = Animation.timingCurve(
      0.2,
      0.8,
      0.2,
      1,
      duration: duration
    )

    if state.layoutOnlyGeneration == shellGeneration {
      activeVisualGeneration = shellGeneration
      withAnimation(animation) {
        presentedLayout = state.snapshot.layout
      }
      return
    }

    guard context.phase == .transitioning else {
      presentedLayout = state.snapshot.layout
      return
    }

    let startsNewHandoff =
      state.handoffStartGeneration == shellGeneration
    if startsNewHandoff {
      var resetTransaction = Transaction()
      resetTransaction.disablesAnimations = true
      withTransaction(resetTransaction) {
        handoffPhase = 0
        activeVisualGeneration = shellGeneration
      }
    } else {
      activeVisualGeneration = shellGeneration
    }

    if usesCrossfade {
      var layoutTransaction = Transaction()
      layoutTransaction.disablesAnimations = true
      withTransaction(layoutTransaction) {
        presentedLayout = state.snapshot.layout
      }
    }

    withAnimation(animation) {
      if !usesCrossfade {
        presentedLayout = state.snapshot.layout
      }
      if startsNewHandoff {
        handoffPhase = 1
      }
    }
    Task { @MainActor [weak state] in
      try? await Task.sleep(
        for: .seconds(duration)
      )
      state?.complete(shellGeneration: shellGeneration)
    }
  }

  private func handleAccessibilityFocusRequest(
    _ request: SurfaceAccessibilityFocusRequest?
  ) {
    guard let request else {
      return
    }
    if case .surfaceContainer = request.destination {
      isSurfaceContainerAccessibilityFocused = true
    }
    guard let announcement = request.announcement,
      let application = NSApp
    else {
      return
    }
    NSAccessibility.post(
      element: application,
      notification: .announcementRequested,
      userInfo: [
        .announcement: announcement,
        .priority: NSAccessibilityPriorityLevel.medium.rawValue,
      ]
    )
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
