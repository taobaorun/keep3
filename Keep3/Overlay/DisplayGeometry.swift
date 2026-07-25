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
  let compactSize: CGSize
  let expandedSize: CGSize
  let floatingTopSpacing: CGFloat

  static let standard = SurfaceMetrics(
    compactSize: CGSize(width: 280, height: 44),
    expandedSize: CGSize(width: 360, height: 216),
    floatingTopSpacing: 8
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
  private static let minimumNotchWingWidth: CGFloat = 96

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
    layout(isExpanded: false).surfaceFrameInScreen
  }

  var expandedFrame: CGRect {
    layout(isExpanded: true).surfaceFrameInScreen
  }

  func layout(isExpanded: Bool) -> SurfaceLayout {
    switch placement {
    case .floating:
      let panelFrame = floatingSurfaceFrame(
        for: isExpanded ? metrics.expandedSize : metrics.compactSize
      )
      return SurfaceLayout(
        panelFrame: panelFrame,
        surfaceFrameInPanel: CGRect(origin: .zero, size: panelFrame.size),
        obstructionSize: nil
      )

    case .notched(let obstructionFrame):
      return notchedLayout(
        obstructionFrame: obstructionFrame,
        isExpanded: isExpanded
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
    isExpanded: Bool
  ) -> SurfaceLayout {
    let screenFrame = descriptor.frame.standardized
    let minimumCompactWidth =
      obstructionFrame.width + (2 * Self.minimumNotchWingWidth)
    let compactWidth = min(
      max(metrics.compactSize.width, minimumCompactWidth),
      screenFrame.width
    )
    let panelSize = CGSize(
      width: min(
        max(metrics.expandedSize.width, compactWidth),
        screenFrame.width
      ),
      height: min(
        max(metrics.expandedSize.height, obstructionFrame.height),
        screenFrame.height
      )
    )
    let panelFrame = topAlignedFrame(
      size: panelSize,
      anchorX: obstructionFrame.midX,
      bounds: screenFrame
    )
    let surfaceSize =
      isExpanded
      ? panelSize
      : CGSize(width: compactWidth, height: obstructionFrame.height)
    let surfaceFrameInPanel = CGRect(
      x: (panelSize.width - surfaceSize.width) / 2,
      y: panelSize.height - surfaceSize.height,
      width: surfaceSize.width,
      height: surfaceSize.height
    )

    return SurfaceLayout(
      panelFrame: panelFrame,
      surfaceFrameInPanel: surfaceFrameInPanel,
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
