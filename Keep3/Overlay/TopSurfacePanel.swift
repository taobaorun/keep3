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

enum SurfaceFrameAnimationKind: Equatable, Sendable {
  case none
  case level
  case mediaTransient

  func animation(reduceMotion: Bool) -> Animation? {
    guard !reduceMotion else {
      return nil
    }
    switch self {
    case .none:
      return nil
    case .level, .mediaTransient:
      return .easeInOut(duration: 0.22)
    }
  }
}

struct SurfaceFrameAnimationContext: Equatable, Sendable {
  let component: SurfaceComponentID
  let level: SurfaceLevel
  let transitionCause: SurfaceTransitionCause
  let focusContentClass: FocusExpandedContentClass?
  let mediaTrackChangeDirection: MediaTrackDirection?
  let mediaTrackPeek: MediaTrackPeek?
}

struct SurfaceFrameAnimationPolicy {
  static func resolve(
    previous: SurfaceFrameAnimationContext?,
    next: SurfaceFrameAnimationContext,
    previousKeyboardNavigationActive: Bool,
    keyboardNavigationActive: Bool
  ) -> SurfaceFrameAnimationKind {
    guard let previous, !previousKeyboardNavigationActive,
      !keyboardNavigationActive
    else {
      return .none
    }
    if [.pointer, .gesture].contains(next.transitionCause),
      previous.level != next.level || previous.component != next.component
    {
      return .level
    }
    if previous.component == .media, next.component == .media,
      previous.mediaTrackChangeDirection != next.mediaTrackChangeDirection
        || previous.mediaTrackPeek != next.mediaTrackPeek
    {
      return .mediaTransient
    }
    return .none
  }
}

extension SurfaceFrameAnimationContext {
  static func focus(_ content: TopSurfaceContent) -> Self {
    Self(
      component: .priorities,
      level: content.level,
      transitionCause: content.navigationContext.transitionCause,
      focusContentClass: content.expandedContentClass,
      mediaTrackChangeDirection: nil,
      mediaTrackPeek: nil
    )
  }

  static func media(_ payload: MediaSurfacePayload) -> Self {
    Self(
      component: .media,
      level: payload.level,
      transitionCause: payload.navigationContext.transitionCause,
      focusContentClass: nil,
      mediaTrackChangeDirection: payload.trackChangeDirection,
      mediaTrackPeek: payload.trackPeek
    )
  }

  static func calendar(_ payload: CalendarSurfacePayload) -> Self {
    Self(
      component: .calendar,
      level: payload.level,
      transitionCause: payload.navigationContext.transitionCause,
      focusContentClass: nil,
      mediaTrackChangeDirection: nil,
      mediaTrackPeek: nil
    )
  }
}

@MainActor
private final class TopSurfaceKeyboardNavigationPresentation:
  ObservableObject
{
  @Published private(set) var isActive = false
  @Published private(set) var guidance: TopSurfaceKeyboardNavigationGuidance?

  func setActive(
    _ isActive: Bool,
    guidance: TopSurfaceKeyboardNavigationGuidance?
  ) {
    self.guidance = isActive ? guidance : nil
    self.isActive = isActive
  }

  func updateGuidance(_ guidance: TopSurfaceKeyboardNavigationGuidance) {
    guard isActive, self.guidance != guidance else {
      return
    }
    self.guidance = guidance
  }
}

@MainActor
private struct TopSurfaceFocusActions {
  let onActivateSurface: () -> Void
  let onRequestKeyboardNavigation: () -> Void
  let onSurfaceNavigation: (SurfaceGestureIntent) -> Void
  let onNavigate: (TopSurfaceBrowseDirection) -> Void
  let onOpenItem: () -> Void
  let onOpenKeep3: () -> Void
}

@MainActor
private final class TopSurfaceFocusPresentation: ObservableObject {
  @Published private(set) var content: TopSurfaceContent
  private var actions: TopSurfaceFocusActions

  init(content: TopSurfaceContent, actions: TopSurfaceFocusActions) {
    self.content = content
    self.actions = actions
  }

  func update(
    content: TopSurfaceContent,
    actions: TopSurfaceFocusActions
  ) {
    self.actions = actions
    guard self.content != content else {
      return
    }
    self.content = content
  }

  func activateSurface() {
    actions.onActivateSurface()
  }

  func requestKeyboardNavigation() {
    actions.onRequestKeyboardNavigation()
  }

  func navigateSurface(_ intent: SurfaceGestureIntent) {
    actions.onSurfaceNavigation(intent)
  }

  func navigate(_ direction: TopSurfaceBrowseDirection) {
    actions.onNavigate(direction)
  }

  func openItem() {
    actions.onOpenItem()
  }

  func openKeep3() {
    actions.onOpenKeep3()
  }
}

@MainActor
final class TopSurfacePanel: NSPanel {
  override var canBecomeKey: Bool {
    keyboardNavigationPresentation.isActive
  }
  override var canBecomeMain: Bool { false }

  private let eventView: TopSurfaceEventView
  private var panelContent: PanelContent
  private var renderedPanelSize: CGSize
  private(set) var renderedPresentationStyle: TopSurfacePresentationStyle
  private(set) var renderedSurfaceFrameInPanel: CGRect
  private(set) var renderedSurfaceFrameAnimationKind: SurfaceFrameAnimationKind
  private var renderedKeyboardNavigationActive = false
  private let keyboardNavigationPresentation: TopSurfaceKeyboardNavigationPresentation
  private var keyboardEventMonitor: Any?

  var renderedContent: TopSurfaceContent {
    guard case .focus(let presentation) = panelContent else {
      preconditionFailure("The panel is currently rendering media")
    }
    return presentation.content
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

  var renderedKeyboardNavigationGuidance: TopSurfaceKeyboardNavigationGuidance? {
    keyboardNavigationPresentation.guidance
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
    onOpenItem: @escaping () -> Void = {},
    onOpenKeep3: @escaping () -> Void = {}
  ) {
    let presentation = TopSurfaceFocusPresentation(
      content: content,
      actions: TopSurfaceFocusActions(
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onSurfaceNavigation: onSurfaceNavigation,
        onNavigate: onNavigate,
        onOpenItem: onOpenItem,
        onOpenKeep3: onOpenKeep3
      )
    )
    self.init(
      contentRect: contentRect,
      surfaceFrameInPanel: surfaceFrameInPanel,
      panelContent: .focus(presentation),
      presentationStyle: presentationStyle,
      onHoverChanged: onHoverChanged,
      onScroll: onScroll,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onDismiss: onDismiss,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem,
      onOpenKeep3: onOpenKeep3,
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
      onOpenKeep3: {},
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
      onOpenKeep3: {},
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
    onOpenKeep3: @escaping () -> Void,
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) {
    let resolvedSurfaceFrame =
      surfaceFrameInPanel ?? CGRect(origin: .zero, size: contentRect.size)
    let keyboardNavigationPresentation =
      TopSurfaceKeyboardNavigationPresentation()
    self.panelContent = panelContent
    renderedPanelSize = contentRect.size
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = resolvedSurfaceFrame
    renderedSurfaceFrameAnimationKind = .none
    self.keyboardNavigationPresentation = keyboardNavigationPresentation
    eventView = TopSurfaceEventView(
      frame: CGRect(origin: .zero, size: contentRect.size),
      activeFrame: resolvedSurfaceFrame,
      rootView: Self.rootView(
        for: panelContent,
        presentationStyle: presentationStyle,
        panelSize: contentRect.size,
        surfaceFrameInPanel: resolvedSurfaceFrame,
        frameAnimationKind: .none,
        keyboardNavigationPresentation: keyboardNavigationPresentation,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onSurfaceNavigation: onSurfaceNavigation,
        onNavigate: onNavigate,
        onOpenItem: onOpenItem,
        onOpenKeep3: onOpenKeep3,
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
    onOpenItem: @escaping () -> Void,
    onOpenKeep3: @escaping () -> Void
  ) {
    let frameAnimationKind = SurfaceFrameAnimationPolicy.resolve(
      previous: panelContent.frameAnimationContext,
      next: .focus(content),
      previousKeyboardNavigationActive: renderedKeyboardNavigationActive,
      keyboardNavigationActive: keyboardNavigationPresentation.isActive
    )
    let currentPresentation = panelContent.focusPresentation
    let needsRootViewUpdate =
      currentPresentation == nil
      || renderedPresentationStyle != presentationStyle
      || renderedSurfaceFrameInPanel != surfaceFrameInPanel
      || renderedPanelSize != eventView.bounds.size

    let actions = TopSurfaceFocusActions(
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem,
      onOpenKeep3: onOpenKeep3
    )
    let presentation: TopSurfaceFocusPresentation
    if let currentPresentation {
      presentation = currentPresentation
      presentation.update(content: content, actions: actions)
    } else {
      presentation = TopSurfaceFocusPresentation(
        content: content,
        actions: actions
      )
    }

    panelContent = .focus(presentation)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    renderedSurfaceFrameAnimationKind = frameAnimationKind
    renderedKeyboardNavigationActive = keyboardNavigationPresentation.isActive
    renderedPanelSize = eventView.bounds.size
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = onNavigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = onOpenItem
    eventView.updateActiveFrame(surfaceFrameInPanel)
    keyboardNavigationPresentation.updateGuidance(
      panelContent.keyboardNavigationGuidance
    )
    guard needsRootViewUpdate else {
      return
    }
    eventView.hostingView.rootView = Self.rootView(
      for: panelContent,
      presentationStyle: presentationStyle,
      panelSize: eventView.bounds.size,
      surfaceFrameInPanel: surfaceFrameInPanel,
      frameAnimationKind: frameAnimationKind,
      keyboardNavigationPresentation: keyboardNavigationPresentation,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem,
      onOpenKeep3: onOpenKeep3,
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
    let frameAnimationKind = SurfaceFrameAnimationPolicy.resolve(
      previous: panelContent.frameAnimationContext,
      next: .media(mediaPayload),
      previousKeyboardNavigationActive: renderedKeyboardNavigationActive,
      keyboardNavigationActive: keyboardNavigationPresentation.isActive
    )
    panelContent = .media(mediaPayload)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    renderedSurfaceFrameAnimationKind = frameAnimationKind
    renderedKeyboardNavigationActive = keyboardNavigationPresentation.isActive
    renderedPanelSize = eventView.bounds.size
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = onNavigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = {}
    eventView.updateActiveFrame(surfaceFrameInPanel)
    keyboardNavigationPresentation.updateGuidance(
      panelContent.keyboardNavigationGuidance
    )
    eventView.hostingView.rootView = Self.rootView(
      for: panelContent,
      presentationStyle: presentationStyle,
      panelSize: eventView.bounds.size,
      surfaceFrameInPanel: surfaceFrameInPanel,
      frameAnimationKind: frameAnimationKind,
      keyboardNavigationPresentation: keyboardNavigationPresentation,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: onNavigate,
      onOpenItem: {},
      onOpenKeep3: {},
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
    let frameAnimationKind = SurfaceFrameAnimationPolicy.resolve(
      previous: panelContent.frameAnimationContext,
      next: .calendar(calendarPayload),
      previousKeyboardNavigationActive: renderedKeyboardNavigationActive,
      keyboardNavigationActive: keyboardNavigationPresentation.isActive
    )
    panelContent = .calendar(calendarPayload)
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    renderedSurfaceFrameAnimationKind = frameAnimationKind
    renderedKeyboardNavigationActive = keyboardNavigationPresentation.isActive
    renderedPanelSize = eventView.bounds.size
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = { _ in }
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = {}
    eventView.updateActiveFrame(surfaceFrameInPanel)
    keyboardNavigationPresentation.updateGuidance(
      panelContent.keyboardNavigationGuidance
    )
    eventView.hostingView.rootView = Self.rootView(
      for: panelContent,
      presentationStyle: presentationStyle,
      panelSize: eventView.bounds.size,
      surfaceFrameInPanel: surfaceFrameInPanel,
      frameAnimationKind: frameAnimationKind,
      keyboardNavigationPresentation: keyboardNavigationPresentation,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onSurfaceNavigation: onSurfaceNavigation,
      onNavigate: { _ in },
      onOpenItem: {},
      onOpenKeep3: {},
      onMediaAction: { _ in }
    )
  }

  private static func rootView(
    for content: PanelContent,
    presentationStyle: TopSurfacePresentationStyle,
    panelSize: CGSize,
    surfaceFrameInPanel: CGRect,
    frameAnimationKind: SurfaceFrameAnimationKind,
    keyboardNavigationPresentation:
      TopSurfaceKeyboardNavigationPresentation,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onSurfaceNavigation: @escaping (SurfaceGestureIntent) -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void,
    onOpenKeep3: @escaping () -> Void,
    onMediaAction: @escaping (MediaSurfaceAction) -> Void
  ) -> AnyView {
    let surfaceSize = surfaceFrameInPanel.size
    let layout = TopSurfaceHostedLayout(
      panelSize: panelSize,
      surfaceFrameInPanel: surfaceFrameInPanel
    )

    switch content {
    case .focus(let presentation):
      return AnyView(
        TopSurfaceFocusRootView(
          layout: layout,
          keyboardNavigationPresentation: keyboardNavigationPresentation,
          presentation: presentation,
          presentationStyle: presentationStyle,
          surfaceSize: surfaceSize,
          frameAnimationKind: frameAnimationKind
        )
      )
    case .media(let media):
      return AnyView(
        TopSurfaceRootView(
          layout: layout,
          isHovered: media.isHovered && media.level != .expanded,
          presentationStyle: presentationStyle,
          frameAnimationKind: frameAnimationKind,
          keyboardNavigationPresentation: keyboardNavigationPresentation,
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
          isHovered: calendar.isHovered && calendar.level != .expanded,
          presentationStyle: presentationStyle,
          frameAnimationKind: frameAnimationKind,
          keyboardNavigationPresentation: keyboardNavigationPresentation,
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
    activateApplication: Bool = true,
    restoresPreviousApplicationOnExit: Bool = true
  ) {
    guard keyboardNavigationPresentation.isActive != isEnabled else {
      return
    }
    keyboardNavigationPresentation.setActive(
      isEnabled,
      guidance: panelContent.keyboardNavigationGuidance
    )
    renderedKeyboardNavigationActive = isEnabled

    guard isEnabled else {
      postKeyboardNavigationAnnouncement(
        restoresPreviousApplicationOnExit
          ? "已退出键盘导航，正在返回上一个应用"
          : "已退出键盘导航"
      )
      if let keyboardEventMonitor {
        NSEvent.removeMonitor(keyboardEventMonitor)
        self.keyboardEventMonitor = nil
      }
      becomesKeyOnlyIfNeeded = true
      if isKeyWindow {
        resignKey()
      }
      orderFrontRegardless()
      return
    }

    becomesKeyOnlyIfNeeded = false
    if activateApplication {
      NSApp.activate()
    }
    postKeyboardNavigationAnnouncement(activationAnnouncement)
    if keyboardEventMonitor == nil {
      keyboardEventMonitor = NSEvent.addLocalMonitorForEvents(
        matching: .keyDown
      ) { [weak self] event in
        guard let self else {
          return event
        }
        return self.routeKeyboardEvent(event) ? nil : event
      }
    }
    makeFirstResponder(eventView)
    makeKeyAndOrderFront(nil)
    Task { @MainActor [weak self] in
      guard let self, self.keyboardNavigationPresentation.isActive else {
        return
      }
      self.makeFirstResponder(self.eventView)
    }
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, routeKeyboardEvent(event) {
      return
    }
    super.sendEvent(event)
  }

  private func routeKeyboardEvent(_ event: NSEvent) -> Bool {
    guard keyboardNavigationPresentation.isActive, isKeyWindow,
      firstResponder === eventView
    else {
      return false
    }
    return eventView.handleKeyboardEvent(event)
  }

  private var activationAnnouncement: String {
    return
      "键盘导航已启用。\(panelContent.keyboardNavigationGuidance.accessibilityInstructions)"
  }

  private func postKeyboardNavigationAnnouncement(_ announcement: String) {
    guard let application = NSApp else {
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

@MainActor
private enum PanelContent {
  case focus(TopSurfaceFocusPresentation)
  case media(MediaSurfacePayload)
  case calendar(CalendarSurfacePayload)

  var focusPresentation: TopSurfaceFocusPresentation? {
    guard case .focus(let presentation) = self else {
      return nil
    }
    return presentation
  }

  var frameAnimationContext: SurfaceFrameAnimationContext {
    switch self {
    case .focus(let presentation):
      .focus(presentation.content)
    case .media(let payload):
      .media(payload)
    case .calendar(let payload):
      .calendar(payload)
    }
  }

  var keyboardNavigationGuidance: TopSurfaceKeyboardNavigationGuidance {
    switch self {
    case .focus(let presentation):
      let content = presentation.content
      return TopSurfaceKeyboardNavigationGuidance.priorities(
        itemCount: content.itemCount,
        level: content.level,
        hasAlternativeComponents: content.navigationContext
          .hasAlternative(to: .priorities)
      )
    case .media(let payload):
      return TopSurfaceKeyboardNavigationGuidance.media(
        capabilities: payload.session?.capabilities ?? [],
        level: payload.level,
        hasAlternativeComponents: payload.navigationContext
          .hasAlternative(to: .media)
      )
    case .calendar(let payload):
      return TopSurfaceKeyboardNavigationGuidance.calendar(
        level: payload.level,
        hasAlternativeComponents: payload.navigationContext
          .hasAlternative(to: .calendar)
      )
    }
  }
}

private struct TopSurfaceFocusRootView: View {
  let layout: TopSurfaceHostedLayout
  @ObservedObject var keyboardNavigationPresentation: TopSurfaceKeyboardNavigationPresentation
  @ObservedObject var presentation: TopSurfaceFocusPresentation
  let presentationStyle: TopSurfacePresentationStyle
  let surfaceSize: CGSize
  let frameAnimationKind: SurfaceFrameAnimationKind

  var body: some View {
    TopSurfaceRootView(
      layout: layout,
      isHovered:
        presentation.content.isHovered
        && presentation.content.level != .expanded,
      presentationStyle: presentationStyle,
      frameAnimationKind: frameAnimationKind,
      keyboardNavigationPresentation: keyboardNavigationPresentation,
      content: TopSurfaceView(
        content: presentation.content,
        presentationStyle: presentationStyle,
        surfaceSize: surfaceSize,
        onActivateSurface: presentation.activateSurface,
        onRequestKeyboardNavigation: presentation.requestKeyboardNavigation,
        onSurfaceNavigation: presentation.navigateSurface,
        onNavigate: presentation.navigate,
        onOpenItem: presentation.openItem,
        onOpenKeep3: presentation.openKeep3
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
  let isHovered: Bool
  let presentationStyle: TopSurfacePresentationStyle
  let frameAnimationKind: SurfaceFrameAnimationKind
  @ObservedObject var keyboardNavigationPresentation: TopSurfaceKeyboardNavigationPresentation
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
        .overlay(alignment: .top) {
          if keyboardNavigationPresentation.isActive,
            let guidance = keyboardNavigationPresentation.guidance
          {
            KeyboardNavigationStatusView(
              guidance: guidance,
              presentationStyle: presentationStyle,
              surfaceSize: layout.surfaceFrameInPanel.size
            )
          }
        }
    }
    .frame(
      width: layout.panelSize.width,
      height: layout.panelSize.height,
      alignment: .topLeading
    )
    .animation(
      frameAnimationKind.animation(reduceMotion: reduceMotion),
      value: layout.surfaceFrameInPanel
    )
    .animation(
      !reduceMotion ? .easeOut(duration: 0.16) : nil,
      value: isHovered
    )
    .environment(
      \.isTopSurfaceKeyboardNavigationActive,
      keyboardNavigationPresentation.isActive
    )
  }
}

private struct KeyboardNavigationStatusView: View {
  let guidance: TopSurfaceKeyboardNavigationGuidance
  let presentationStyle: TopSurfacePresentationStyle
  let surfaceSize: CGSize

  var body: some View {
    Group {
      switch presentationStyle {
      case .floatingCapsule:
        HStack(spacing: 4) {
          Image(systemName: "keyboard")
          Text(guidance.visibleDirections)
          Text("esc")
        }
        .padding(.horizontal, 6)
        .frame(height: 11)
        .background(.black.opacity(0.88), in: Capsule())
        .overlay {
          Capsule().stroke(.white.opacity(0.28), lineWidth: 0.5)
        }
        .padding(.top, 2)
      case .notchAttached(let notchSize):
        let layout = NotchCompactContentLayout(
          surfaceSize: surfaceSize,
          obstructionSize: notchSize
        )
        let tokens =
          guidance.visibleDirections.split(separator: " ").map(String.init)
          + ["esc"]
        let splitIndex = (tokens.count + 1) / 2
        HStack(spacing: 0) {
          wingLegend(Array(tokens[..<splitIndex]))
            .frame(width: layout.leftWingFrame.width)
          Color.clear
            .frame(width: layout.obstructionFrame.width)
          wingLegend(Array(tokens[splitIndex...]))
            .frame(width: layout.rightWingFrame.width)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 2)
      }
    }
    .font(.system(size: 7, weight: .semibold, design: .monospaced))
    .foregroundStyle(.white.opacity(0.82))
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "键盘导航已启用。\(guidance.accessibilityInstructions)"
    )
    .accessibilityIdentifier("overlay.keyboardNavigationStatus")
  }

  private func wingLegend(_ tokens: [String]) -> some View {
    Text(tokens.joined(separator: " "))
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .frame(maxWidth: .infinity)
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
