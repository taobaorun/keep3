import AppKit
import CoreGraphics

struct DisplayInsets: Equatable {
  let top: CGFloat
  let left: CGFloat
  let bottom: CGFloat
  let right: CGFloat

  static let zero = DisplayInsets(top: 0, left: 0, bottom: 0, right: 0)

  init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
    self.top = top
    self.left = left
    self.bottom = bottom
    self.right = right
  }

  init(_ insets: NSEdgeInsets) {
    self.init(
      top: insets.top,
      left: insets.left,
      bottom: insets.bottom,
      right: insets.right
    )
  }
}

struct DisplayDescriptor: Equatable {
  let frame: CGRect
  let visibleFrame: CGRect
  let safeAreaInsets: DisplayInsets
  let auxiliaryTopLeftArea: CGRect?
  let auxiliaryTopRightArea: CGRect?

  init(
    frame: CGRect,
    visibleFrame: CGRect,
    safeAreaInsets: DisplayInsets,
    auxiliaryTopLeftArea: CGRect?,
    auxiliaryTopRightArea: CGRect?
  ) {
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.safeAreaInsets = safeAreaInsets
    self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
    self.auxiliaryTopRightArea = auxiliaryTopRightArea
  }

  init(screen: NSScreen) {
    self.init(
      frame: screen.frame,
      visibleFrame: screen.visibleFrame,
      safeAreaInsets: DisplayInsets(screen.safeAreaInsets),
      auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
      auxiliaryTopRightArea: screen.auxiliaryTopRightArea
    )
  }
}

enum SurfacePlacement: Equatable {
  case notched(obstructionFrame: CGRect)
  case floating
}

struct SurfaceMetrics: Equatable {
  enum NotchedCompactSizing: Equatable {
    case flexible(minimumWingWidth: CGFloat)
    case fixedWingWidth(CGFloat)

    func width(
      obstructionWidth: CGFloat,
      preferredWidth: CGFloat,
      maximumWidth: CGFloat
    ) -> CGFloat {
      let wingWidth: CGFloat
      let includesPreferredWidth: Bool

      switch self {
      case .flexible(let minimumWingWidth):
        wingWidth = minimumWingWidth
        includesPreferredWidth = true
      case .fixedWingWidth(let fixedWingWidth):
        wingWidth = fixedWingWidth
        includesPreferredWidth = false
      }

      let contentWidth = obstructionWidth + (2 * max(0, wingWidth))
      return min(
        includesPreferredWidth
          ? max(preferredWidth, contentWidth)
          : contentWidth,
        maximumWidth
      )
    }
  }

  let compactSize: CGSize
  let expandedSize: CGSize
  let floatingTopSpacing: CGFloat
  let notchedCompactSizing: NotchedCompactSizing

  init(
    compactSize: CGSize,
    expandedSize: CGSize,
    floatingTopSpacing: CGFloat,
    notchedCompactSizing: NotchedCompactSizing = .flexible(
      minimumWingWidth: 96
    )
  ) {
    self.compactSize = compactSize
    self.expandedSize = expandedSize
    self.floatingTopSpacing = floatingTopSpacing
    self.notchedCompactSizing = notchedCompactSizing
  }

  static let standard = SurfaceMetrics(
    compactSize: CGSize(width: 280, height: 44),
    expandedSize: CGSize(width: 360, height: 216),
    floatingTopSpacing: 8,
    notchedCompactSizing: .flexible(minimumWingWidth: 96)
  )

  static let media = SurfaceMetrics(
    compactSize: CGSize(width: 310, height: 44),
    expandedSize: CGSize(width: 344, height: 170),
    floatingTopSpacing: 8,
    notchedCompactSizing: .fixedWingWidth(37)
  )
}

struct SurfaceLayout: Equatable {
  let panelFrame: CGRect
  let surfaceFrameInPanel: CGRect
  let obstructionSize: CGSize?

  var surfaceFrameInScreen: CGRect {
    surfaceFrameInPanel.offsetBy(
      dx: panelFrame.minX,
      dy: panelFrame.minY
    )
  }
}

struct DisplayGeometry: Equatable {
  let descriptor: DisplayDescriptor
  let metrics: SurfaceMetrics

  init(descriptor: DisplayDescriptor, metrics: SurfaceMetrics = .standard) {
    self.descriptor = descriptor
    self.metrics = metrics
  }

  var placement: SurfacePlacement {
    guard let obstructionFrame else {
      return .floating
    }

    return .notched(obstructionFrame: obstructionFrame)
  }

  var compactFrame: CGRect {
    layout(level: .compact).surfaceFrameInScreen
  }

  var expandedFrame: CGRect {
    layout(level: .expanded).surfaceFrameInScreen
  }

  var hardwareFrame: CGRect {
    layout(level: .hardware).surfaceFrameInScreen
  }

  func layout(isExpanded: Bool) -> SurfaceLayout {
    layout(level: isExpanded ? .expanded : .compact)
  }

  func layout(level: SurfaceLevel) -> SurfaceLayout {
    switch placement {
    case .floating:
      let requestedSize: CGSize
      switch level {
      case .hardware:
        requestedSize = CGSize(
          width: min(metrics.compactSize.width, 160),
          height: min(metrics.compactSize.height, 8)
        )
      case .compact:
        requestedSize = metrics.compactSize
      case .expanded:
        requestedSize = metrics.expandedSize
      }
      let panelFrame = floatingSurfaceFrame(
        for: requestedSize
      )
      return SurfaceLayout(
        panelFrame: panelFrame,
        surfaceFrameInPanel: CGRect(origin: .zero, size: panelFrame.size),
        obstructionSize: nil
      )

    case .notched(let obstructionFrame):
      return notchedLayout(
        obstructionFrame: obstructionFrame,
        level: level
      )
    }
  }

  private var obstructionFrame: CGRect? {
    let screenFrame = descriptor.frame.standardized

    guard
      descriptor.safeAreaInsets.top > 0,
      let leftArea = descriptor.auxiliaryTopLeftArea?.standardized,
      let rightArea = descriptor.auxiliaryTopRightArea?.standardized,
      isUsable(leftArea, within: screenFrame),
      isUsable(rightArea, within: screenFrame),
      abs(leftArea.maxY - screenFrame.maxY) <= 1,
      abs(rightArea.maxY - screenFrame.maxY) <= 1,
      abs(leftArea.minY - rightArea.minY) <= 1,
      leftArea.maxX < rightArea.minX
    else {
      return nil
    }

    let expectedMinimumY = screenFrame.maxY - descriptor.safeAreaInsets.top
    guard abs(leftArea.minY - expectedMinimumY) <= 1 else {
      return nil
    }

    return CGRect(
      x: leftArea.maxX,
      y: leftArea.minY,
      width: rightArea.minX - leftArea.maxX,
      height: screenFrame.maxY - leftArea.minY
    )
  }

  private var usableFrame: CGRect {
    let screenFrame = descriptor.frame.standardized
    let visibleFrame = descriptor.visibleFrame.standardized.intersection(screenFrame)

    guard !visibleFrame.isNull, visibleFrame.width > 0, visibleFrame.height > 0 else {
      return screenFrame
    }

    return visibleFrame
  }

  private func notchedLayout(
    obstructionFrame: CGRect,
    level: SurfaceLevel
  ) -> SurfaceLayout {
    let screenFrame = descriptor.frame.standardized
    let compactWidth = metrics.notchedCompactSizing.width(
      obstructionWidth: obstructionFrame.width,
      preferredWidth: metrics.compactSize.width,
      maximumWidth: screenFrame.width
    )
    let panelSize: CGSize
    switch level {
    case .hardware:
      panelSize = obstructionFrame.size
    case .compact:
      panelSize = CGSize(
        width: compactWidth,
        height: obstructionFrame.height
      )
    case .expanded:
      panelSize = CGSize(
        width: min(
          max(metrics.expandedSize.width, obstructionFrame.width),
          screenFrame.width
        ),
        height: min(
          max(metrics.expandedSize.height, obstructionFrame.height),
          screenFrame.height
        )
      )
    }
    let panelFrame = topAlignedFrame(
      size: panelSize,
      anchorX: obstructionFrame.midX,
      bounds: screenFrame
    )

    return SurfaceLayout(
      panelFrame: panelFrame,
      surfaceFrameInPanel: CGRect(origin: .zero, size: panelSize),
      obstructionSize: obstructionFrame.size
    )
  }

  private func floatingSurfaceFrame(for requestedSize: CGSize) -> CGRect {
    let bounds = usableFrame
    let topY = bounds.maxY - metrics.floatingTopSpacing
    let size = CGSize(
      width: min(max(0, requestedSize.width), bounds.width),
      height: min(
        max(0, requestedSize.height),
        max(0, topY - bounds.minY)
      )
    )

    let maximumX = bounds.maxX - size.width
    let x = min(
      max(descriptor.frame.midX - (size.width / 2), bounds.minX),
      maximumX
    )
    let y = max(topY - size.height, bounds.minY)

    return CGRect(origin: CGPoint(x: x, y: y), size: size)
  }

  private func topAlignedFrame(
    size: CGSize,
    anchorX: CGFloat,
    bounds: CGRect
  ) -> CGRect {
    let maximumX = bounds.maxX - size.width
    let x = min(
      max(anchorX - (size.width / 2), bounds.minX),
      maximumX
    )
    return CGRect(
      x: x,
      y: bounds.maxY - size.height,
      width: size.width,
      height: size.height
    )
  }

  private func isUsable(_ area: CGRect, within screenFrame: CGRect) -> Bool {
    area.width > 0
      && area.height > 0
      && area.minX >= screenFrame.minX
      && area.maxX <= screenFrame.maxX
      && area.minY >= screenFrame.minY
      && area.maxY <= screenFrame.maxY
  }
}
