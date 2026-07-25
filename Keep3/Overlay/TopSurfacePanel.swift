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
  private(set) var renderedContent: TopSurfaceContent
  private(set) var renderedPresentationStyle: TopSurfacePresentationStyle
  private(set) var renderedSurfaceFrameInPanel: CGRect
  private var keyboardNavigationEnabled = false
  private var keyboardEventMonitor: Any?

  init(
    contentRect: CGRect,
    surfaceFrameInPanel: CGRect? = nil,
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
    let resolvedSurfaceFrame =
      surfaceFrameInPanel ?? CGRect(origin: .zero, size: contentRect.size)
    renderedContent = content
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = resolvedSurfaceFrame
    eventView = TopSurfaceEventView(
      frame: CGRect(origin: .zero, size: contentRect.size),
      activeFrame: resolvedSurfaceFrame,
      rootView: TopSurfaceView(
        content: content,
        presentationStyle: presentationStyle,
        surfaceSize: resolvedSurfaceFrame.size,
        onActivateSurface: onActivateSurface,
        onRequestKeyboardNavigation: onRequestKeyboardNavigation,
        onNavigate: onNavigate,
        onOpenItem: onOpenItem
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
    onScroll: @escaping (CGFloat, TopSurfaceGesturePhase) -> Void,
    onActivateSurface: @escaping () -> Void,
    onRequestKeyboardNavigation: @escaping () -> Void,
    onDismiss: @escaping () -> Void,
    onNavigate: @escaping (TopSurfaceBrowseDirection) -> Void,
    onOpenItem: @escaping () -> Void
  ) {
    renderedContent = content
    renderedPresentationStyle = presentationStyle
    renderedSurfaceFrameInPanel = surfaceFrameInPanel
    hasShadow = presentationStyle.hasPanelShadow
    eventView.onHoverChanged = onHoverChanged
    eventView.onScroll = onScroll
    eventView.onNavigate = onNavigate
    eventView.onDismiss = onDismiss
    eventView.onOpenItem = onOpenItem
    eventView.updateActiveFrame(surfaceFrameInPanel)
    eventView.hostingView.rootView = TopSurfaceView(
      content: content,
      presentationStyle: presentationStyle,
      surfaceSize: surfaceFrameInPanel.size,
      onActivateSurface: onActivateSurface,
      onRequestKeyboardNavigation: onRequestKeyboardNavigation,
      onNavigate: onNavigate,
      onOpenItem: onOpenItem
    )

    if !content.isExpanded {
      setKeyboardNavigationEnabled(false)
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

@MainActor
private final class TopSurfaceEventView: NSView {
  override var acceptsFirstResponder: Bool { true }

  let hostingView: NSHostingView<TopSurfaceView>
  var onHoverChanged: (Bool) -> Void = { _ in }
  var onScroll: (CGFloat, TopSurfaceGesturePhase) -> Void = { _, _ in }
  var onNavigate: (TopSurfaceBrowseDirection) -> Void = { _ in }
  var onDismiss: () -> Void = {}
  var onOpenItem: () -> Void = {}

  private var hoverTrackingArea: NSTrackingArea?
  private var activeFrame: CGRect

  init(
    frame: CGRect,
    activeFrame: CGRect,
    rootView: TopSurfaceView
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
    let delta = navigationDelta(for: event)

    if event.phase.isEmpty {
      guard event.momentumPhase.isEmpty else {
        return
      }
      onScroll(delta, .began)
      onScroll(0, .ended)
      return
    }

    if event.phase.contains(.began) {
      onScroll(delta, .began)
    } else if event.phase.contains(.changed)
      || event.phase.contains(.stationary)
    {
      onScroll(delta, .changed)
    } else if event.phase.contains(.ended) {
      onScroll(0, .ended)
    } else if event.phase.contains(.cancelled) {
      onScroll(0, .cancelled)
    }
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

  private func navigationDelta(for event: NSEvent) -> CGFloat {
    let horizontal = event.scrollingDeltaX
    let vertical = event.scrollingDeltaY
    let dominantDelta =
      abs(horizontal) > abs(vertical) ? -horizontal : vertical

    guard !event.hasPreciseScrollingDeltas else {
      return dominantDelta
    }
    return dominantDelta * 20
  }
}
