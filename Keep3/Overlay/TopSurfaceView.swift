import SwiftUI

struct TopSurfaceKeyboardNavigationGuidance: Equatable, Sendable {
  let visibleDirections: String
  let accessibilityInstructions: String

  static func priorities(itemCount: Int) -> Self {
    let horizontal =
      itemCount > 1 ? "←/→ 浏览重点，" : ""
    return Self(
      visibleDirections: itemCount > 1 ? "← → ↑ ↓ ↩" : "↑ ↓ ↩",
      accessibilityInstructions:
        "\(horizontal)↑/↓ 切换表面，Return 打开当前重点，Escape 退出并返回上一个应用"
    )
  }

  static func media(
    canGoToPreviousTrack: Bool,
    canGoToNextTrack: Bool
  ) -> Self {
    var visibleDirections: [String] = []
    var instructions: [String] = []
    if canGoToPreviousTrack {
      visibleDirections.append("←")
      instructions.append("← 上一首")
    }
    if canGoToNextTrack {
      visibleDirections.append("→")
      instructions.append("→ 下一首")
    }
    visibleDirections.append(contentsOf: ["↑", "↓"])
    instructions.append("↑ 返回普通播放器")
    instructions.append("↓ 切换到下一个表面")
    instructions.append("Escape 退出并返回上一个应用")
    return Self(
      visibleDirections: visibleDirections.joined(separator: " "),
      accessibilityInstructions: instructions.joined(separator: "，")
    )
  }

  static let calendar = Self(
    visibleDirections: "↑ ↓",
    accessibilityInstructions:
      "↑/↓ 切换表面，Escape 退出并返回上一个应用"
  )
}

private struct TopSurfaceKeyboardNavigationActiveKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var isTopSurfaceKeyboardNavigationActive: Bool {
    get { self[TopSurfaceKeyboardNavigationActiveKey.self] }
    set { self[TopSurfaceKeyboardNavigationActiveKey.self] = newValue }
  }
}

struct TopSurfaceKeyboardNavigationButton: View {
  let guidance: TopSurfaceKeyboardNavigationGuidance
  let onActivate: () -> Void

  @Environment(\.isTopSurfaceKeyboardNavigationActive) private
    var isActive

  var body: some View {
    Button(action: onActivate) {
      Label(
        isActive
          ? "已启用 · \(guidance.visibleDirections)"
          : guidance.visibleDirections,
        systemImage: "keyboard"
      )
      .font(.caption2.weight(.semibold))
      .foregroundStyle(isActive ? Color.green : Color.white.opacity(0.64))
      .padding(.horizontal, 9)
      .frame(height: 24)
      .background(
        isActive ? Color.green.opacity(0.14) : Color.white.opacity(0.065),
        in: Capsule()
      )
      .overlay {
        Capsule()
          .stroke(
            isActive ? Color.green.opacity(0.32) : Color.clear,
            lineWidth: 0.5
          )
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      isActive ? "键盘导航已启用" : "启用键盘导航"
    )
    .accessibilityHint(
      isActive
        ? guidance.accessibilityInstructions
        : "激活 Keep3 后，\(guidance.accessibilityInstructions)"
    )
    .accessibilityValue(isActive ? "已启用" : "未启用")
    .help(guidance.accessibilityInstructions)
  }
}

enum TopSurfacePresentationStyle: Equatable, Sendable {
  case notchAttached(notchSize: CGSize)
  case floatingCapsule

  var hasPanelShadow: Bool {
    switch self {
    case .notchAttached:
      false
    case .floatingCapsule:
      true
    }
  }
}

struct NotchCompactContentLayout: Equatable {
  let surfaceSize: CGSize
  let obstructionSize: CGSize

  var leftWingFrame: CGRect {
    CGRect(x: 0, y: 0, width: wingWidth, height: surfaceSize.height)
  }

  var obstructionFrame: CGRect {
    CGRect(
      x: wingWidth,
      y: 0,
      width: clampedObstructionWidth,
      height: min(obstructionSize.height, surfaceSize.height)
    )
  }

  var rightWingFrame: CGRect {
    CGRect(
      x: obstructionFrame.maxX,
      y: 0,
      width: wingWidth,
      height: surfaceSize.height
    )
  }

  private var clampedObstructionWidth: CGFloat {
    min(max(0, obstructionSize.width), surfaceSize.width)
  }

  private var wingWidth: CGFloat {
    max(0, (surfaceSize.width - clampedObstructionWidth) / 2)
  }
}

struct ExpandedSurfaceContentLayout: Equatable {
  let surfaceSize: CGSize
  let topInset: CGFloat

  var headerFrame: CGRect {
    CGRect(
      x: Self.horizontalPadding,
      y: resolvedTopInset + Self.topPadding,
      width: contentWidth,
      height: Self.headerHeight
    )
  }

  var titleFrame: CGRect {
    CGRect(
      x: Self.horizontalPadding,
      y: headerFrame.maxY + Self.titleTopSpacing,
      width: contentWidth,
      height: Self.titleHeight
    )
  }

  var supportingContentFrame: CGRect {
    let originY = titleFrame.maxY + Self.supportingContentTopSpacing
    let maximumY =
      footerFrame.minY
      - Self.footerTopSpacing
      - Self.separatorHeight
      - Self.separatorTopSpacing

    return CGRect(
      x: Self.horizontalPadding,
      y: originY,
      width: contentWidth,
      height: max(0, maximumY - originY)
    )
  }

  var separatorFrame: CGRect {
    CGRect(
      x: Self.horizontalPadding,
      y: supportingContentFrame.maxY + Self.separatorTopSpacing,
      width: contentWidth,
      height: Self.separatorHeight
    )
  }

  var footerFrame: CGRect {
    CGRect(
      x: Self.horizontalPadding,
      y: max(
        0,
        surfaceSize.height - Self.bottomPadding - Self.footerHeight
      ),
      width: contentWidth,
      height: Self.footerHeight
    )
  }

  private static let horizontalPadding: CGFloat = 20
  private static let topPadding: CGFloat = 10
  private static let bottomPadding: CGFloat = 10
  private static let headerHeight: CGFloat = 14
  private static let titleTopSpacing: CGFloat = 4
  private static let titleHeight: CGFloat = 22
  private static let supportingContentTopSpacing: CGFloat = 6
  private static let separatorTopSpacing: CGFloat = 7
  private static let separatorHeight: CGFloat = 1
  private static let footerTopSpacing: CGFloat = 7
  private static let footerHeight: CGFloat = 28

  private var resolvedTopInset: CGFloat {
    min(max(0, topInset), surfaceSize.height)
  }

  private var contentWidth: CGFloat {
    max(0, surfaceSize.width - (2 * Self.horizontalPadding))
  }
}

struct TopSurfaceShape: Shape {
  let presentationStyle: TopSurfacePresentationStyle
  private var topShoulderInset: CGFloat
  private var topShoulderDepth: CGFloat
  private var bottomRadius: CGFloat
  private var floatingRadius: CGFloat

  init(
    presentationStyle: TopSurfacePresentationStyle,
    isExpanded: Bool,
    isQuickPeek: Bool = false
  ) {
    self.presentationStyle = presentationStyle
    if isExpanded {
      topShoulderInset = 14
      topShoulderDepth = 14
      bottomRadius = 24
      floatingRadius = 24
    } else if isQuickPeek {
      topShoulderInset = 7
      topShoulderDepth = 7
      bottomRadius = 19
      floatingRadius = 22
    } else {
      topShoulderInset = 6
      topShoulderDepth = 6
      bottomRadius = 14
      floatingRadius = 22
    }
  }

  var animatableData:
    AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
  {
    get {
      AnimatablePair(
        topShoulderInset,
        AnimatablePair(
          topShoulderDepth,
          AnimatablePair(bottomRadius, floatingRadius)
        )
      )
    }
    set {
      topShoulderInset = newValue.first
      topShoulderDepth = newValue.second.first
      bottomRadius = newValue.second.second.first
      floatingRadius = newValue.second.second.second
    }
  }

  func path(in rect: CGRect) -> Path {
    switch presentationStyle {
    case .floatingCapsule:
      return RoundedRectangle(
        cornerRadius: floatingRadius,
        style: .continuous
      ).path(in: rect)
    case .notchAttached:
      return topAttachedPath(in: rect)
    }
  }

  private func topAttachedPath(in rect: CGRect) -> Path {
    let shoulderInset = min(topShoulderInset, rect.width / 4)
    let shoulderDepth = min(topShoulderDepth, rect.height / 2)
    let resolvedBottomRadius = min(
      bottomRadius,
      rect.width / 2,
      max(0, rect.height - shoulderDepth)
    )

    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addCurve(
      to: CGPoint(
        x: rect.maxX - shoulderInset,
        y: rect.minY + shoulderDepth
      ),
      control1: CGPoint(
        x: rect.maxX - (shoulderInset * 0.12),
        y: rect.minY
      ),
      control2: CGPoint(
        x: rect.maxX - shoulderInset,
        y: rect.minY + (shoulderDepth * 0.35)
      )
    )
    path.addLine(
      to: CGPoint(
        x: rect.maxX - shoulderInset,
        y: rect.maxY - resolvedBottomRadius
      )
    )
    path.addQuadCurve(
      to: CGPoint(
        x: rect.maxX - shoulderInset - resolvedBottomRadius,
        y: rect.maxY
      ),
      control: CGPoint(x: rect.maxX - shoulderInset, y: rect.maxY)
    )
    path.addLine(
      to: CGPoint(
        x: rect.minX + shoulderInset + resolvedBottomRadius,
        y: rect.maxY
      )
    )
    path.addQuadCurve(
      to: CGPoint(
        x: rect.minX + shoulderInset,
        y: rect.maxY - resolvedBottomRadius
      ),
      control: CGPoint(x: rect.minX + shoulderInset, y: rect.maxY)
    )
    path.addLine(
      to: CGPoint(
        x: rect.minX + shoulderInset,
        y: rect.minY + shoulderDepth
      )
    )
    path.addCurve(
      to: CGPoint(x: rect.minX, y: rect.minY),
      control1: CGPoint(
        x: rect.minX + shoulderInset,
        y: rect.minY + (shoulderDepth * 0.35)
      ),
      control2: CGPoint(
        x: rect.minX + (shoulderInset * 0.12),
        y: rect.minY
      )
    )
    path.closeSubpath()
    return path
  }
}

enum SurfaceAccessibilityFocusDestination: Equatable, Sendable {
  case compactMedia
}

struct SurfaceAccessibilityNavigationAction: Equatable, Sendable {
  let name: String
  let intent: SurfaceGestureIntent
  let focusDestination: SurfaceAccessibilityFocusDestination?
  let announcement: String?

  static func expandedRetreat(
    for component: SurfaceComponentID
  ) -> Self {
    if component == .media {
      return Self(
        name: String(localized: "返回普通播放器"),
        intent: .retreatDepth,
        focusDestination: .compactMedia,
        announcement: String(localized: "已返回普通播放器")
      )
    }
    return Self(
      name: String(localized: "上一个组件"),
      intent: .previousComponent,
      focusDestination: nil,
      announcement: nil
    )
  }
}

struct SurfaceAccessibilityNavigationModifier: ViewModifier {
  let component: SurfaceComponentID
  let level: SurfaceLevel
  let onNavigate: (SurfaceGestureIntent) -> Void
  let onActionPerformed: (SurfaceAccessibilityNavigationAction) -> Void

  init(
    component: SurfaceComponentID,
    level: SurfaceLevel,
    onNavigate: @escaping (SurfaceGestureIntent) -> Void,
    onActionPerformed: @escaping (
      SurfaceAccessibilityNavigationAction
    ) -> Void = { _ in }
  ) {
    self.component = component
    self.level = level
    self.onNavigate = onNavigate
    self.onActionPerformed = onActionPerformed
  }

  @ViewBuilder
  func body(content: Content) -> some View {
    switch level {
    case .hardware:
      content.accessibilityAction(named: Text("展开一级")) {
        onNavigate(.advanceDepth)
      }
    case .compact:
      content
        .accessibilityAction(named: Text("展开一级")) {
          onNavigate(.advanceDepth)
        }
        .accessibilityAction(named: Text("收起一级")) {
          onNavigate(.retreatDepth)
        }
    case .expanded:
      let retreatAction =
        SurfaceAccessibilityNavigationAction.expandedRetreat(
          for: component
        )
      content
        .accessibilityAction(named: Text("下一个组件")) {
          onNavigate(.advanceDepth)
        }
        .accessibilityAction(named: Text(retreatAction.name)) {
          onNavigate(retreatAction.intent)
          onActionPerformed(retreatAction)
        }
    }
  }
}

struct TopSurfaceView: View {
  let content: TopSurfaceContent
  let presentationStyle: TopSurfacePresentationStyle
  let surfaceSize: CGSize
  let onActivateSurface: () -> Void
  let onRequestKeyboardNavigation: () -> Void
  let onSurfaceNavigation: (SurfaceGestureIntent) -> Void
  let onNavigate: (TopSurfaceBrowseDirection) -> Void
  let onOpenItem: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private
    var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityDifferentiateWithoutColor) private
    var differentiateWithoutColor

  var body: some View {
    surfaceBody
      .frame(width: surfaceSize.width, height: surfaceSize.height)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .accessibilityElement(children: .contain)
      .accessibilityLabel(accessibilitySummary)
      .modifier(
        SurfaceAccessibilityNavigationModifier(
          component: .priorities,
          level: content.level,
          onNavigate: onSurfaceNavigation
        )
      )
  }

  private var surfaceBody: some View {
    Group {
      if content.level == .hardware {
        Color.clear
      } else if content.isExpanded {
        expandedContent
          .transition(surfaceTransition)
      } else {
        compactContent
          .transition(surfaceTransition)
      }
    }
    .animation(contentAnimation, value: content.transitionIdentity)
    .animation(contentAnimation, value: content.isExpanded)
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      surfaceShape
        .fill(.black.opacity(surfaceBackgroundOpacity))
        .animation(shapeAnimation, value: content.isExpanded)
    }
    .mask {
      surfaceShape
        .fill(.white)
        .animation(shapeAnimation, value: content.isExpanded)
    }
    .overlay(alignment: .top) {
      if case .notchAttached = presentationStyle {
        Rectangle()
          .fill(.black)
          .frame(height: 1)
      }
    }
  }

  @ViewBuilder
  private var compactContent: some View {
    switch presentationStyle {
    case .notchAttached(let notchSize):
      notchedCompactContent(notchSize: notchSize)
    case .floatingCapsule:
      floatingCompactContent
    }
  }

  private var floatingCompactContent: some View {
    compactButton {
      HStack(spacing: 8) {
        focusMarker

        Text(content.item.title)
          .font(.subheadline.weight(.medium))
          .lineLimit(1)
          .truncationMode(.tail)
          .id(content.transitionIdentity)
          .transition(titleTransition)
      }
      .padding(.horizontal, 16)
    }
  }

  private func notchedCompactContent(notchSize: CGSize) -> some View {
    let layout = NotchCompactContentLayout(
      surfaceSize: surfaceSize,
      obstructionSize: notchSize
    )

    return compactButton {
      HStack(spacing: 0) {
        focusMarker
          .foregroundStyle(.white.opacity(0.78))
          .frame(width: layout.leftWingFrame.width)

        Color.clear
          .frame(width: layout.obstructionFrame.width)
          .accessibilityHidden(true)

        Text(content.item.title)
          .font(.caption.weight(.medium))
          .lineLimit(1)
          .truncationMode(.tail)
          .minimumScaleFactor(0.72)
          .frame(width: layout.rightWingFrame.width)
          .id(content.transitionIdentity)
          .transition(titleTransition)
      }
    }
  }

  private func compactButton<Label: View>(
    @ViewBuilder label: () -> Label
  ) -> some View {
    Button(action: onActivateSurface) {
      label()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(content.item.title)
    .accessibilityHint("展开当前可见重点")
    .accessibilityIdentifier("overlay.compact")
  }

  private var expandedContent: some View {
    let layout = ExpandedSurfaceContentLayout(
      surfaceSize: surfaceSize,
      topInset: expandedTopInset
    )

    return VStack(alignment: .leading, spacing: 0) {
      expandedHeader
        .frame(height: layout.headerFrame.height)

      expandedTitle
        .frame(height: layout.titleFrame.height)
        .padding(.top, layout.titleFrame.minY - layout.headerFrame.maxY)

      supportingContent
        .frame(height: layout.supportingContentFrame.height)
        .padding(
          .top,
          layout.supportingContentFrame.minY - layout.titleFrame.maxY
        )

      Rectangle()
        .fill(.white.opacity(0.1))
        .frame(height: layout.separatorFrame.height)
        .padding(
          .top,
          layout.separatorFrame.minY
            - layout.supportingContentFrame.maxY
        )
        .accessibilityHidden(true)

      expandedFooter
        .frame(height: layout.footerFrame.height)
        .padding(
          .top,
          layout.footerFrame.minY - layout.separatorFrame.maxY
        )
    }
    .padding(.horizontal, layout.headerFrame.minX)
    .padding(.top, layout.headerFrame.minY)
    .padding(.bottom, surfaceSize.height - layout.footerFrame.maxY)
  }

  private var expandedHeader: some View {
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        focusMarker
        Text(content.isCurrentFocus ? "当前重点" : "第 \(content.position) 项重点")
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white.opacity(0.78))

      Spacer(minLength: 8)

      Text("\(content.position) / \(content.itemCount)")
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.white.opacity(0.48))
        .accessibilityLabel(
          "第 \(content.position) 件，共 \(content.itemCount) 件"
        )
    }
  }

  private var expandedTitle: some View {
    Button(action: onOpenItem) {
      HStack(spacing: 6) {
        Text(content.item.title)
          .font(.system(size: 18, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.tail)
          .minimumScaleFactor(0.75)
          .id(content.transitionIdentity)
          .transition(titleTransition)

        Image(systemName: "arrow.up.right")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(.white.opacity(0.46))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("打开 \(content.item.title)")
    .accessibilityIdentifier("overlay.openItem")
  }

  @ViewBuilder
  private var supportingContent: some View {
    if content.displayDetails != nil || !content.displaySubitems.isEmpty {
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 5) {
          if let details = content.displayDetails {
            Text(details)
              .font(.caption)
              .foregroundStyle(.white.opacity(0.76))
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          ForEach(
            Array(content.displaySubitems.enumerated()),
            id: \.offset
          ) { _, subitem in
            HStack(alignment: .firstTextBaseline, spacing: 7) {
              Circle()
                .fill(.white.opacity(0.36))
                .frame(width: 3, height: 3)

              Text(subitem)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
      }
      .scrollIndicators(.hidden)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.white.opacity(0.055))
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(.white.opacity(0.075), lineWidth: 0.5)
          }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    } else {
      Color.clear
        .accessibilityHidden(true)
    }
  }

  private var expandedFooter: some View {
    HStack(spacing: 12) {
      if content.itemCount > 1 {
        navigationButton(
          systemName: "chevron.left",
          label: "上一件",
          direction: .previous
        )
      } else {
        navigationPlaceholder
      }

      Spacer(minLength: 8)

      TopSurfaceKeyboardNavigationButton(
        guidance: .priorities(itemCount: content.itemCount),
        onActivate: onRequestKeyboardNavigation
      )
      .accessibilityIdentifier("overlay.keyboard")

      Spacer(minLength: 8)

      if content.itemCount > 1 {
        navigationButton(
          systemName: "chevron.right",
          label: "下一件",
          direction: .next
        )
      } else {
        navigationPlaceholder
      }
    }
  }

  private var navigationPlaceholder: some View {
    Color.clear
      .frame(width: 28, height: 28)
      .accessibilityHidden(true)
  }

  private func navigationButton(
    systemName: String,
    label: String,
    direction: TopSurfaceBrowseDirection
  ) -> some View {
    Button {
      onNavigate(direction)
    } label: {
      Image(systemName: systemName)
        .font(.system(size: 9, weight: .bold))
        .frame(width: 28, height: 28)
        .background(.white.opacity(0.085), in: Circle())
        .overlay {
          Circle()
            .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityIdentifier(
      direction == .previous ? "overlay.previous" : "overlay.next"
    )
  }

  private var accessibilitySummary: String {
    let focusDescription = content.isCurrentFocus ? "当前重点" : "次要重点，第 \(content.position) 项"
    return
      "\(focusDescription)，\(content.item.title)，第 \(content.position) 件，共 \(content.itemCount) 件"
  }

  private var signatureTransition: SignatureSurfaceTransition {
    SignatureSurfaceTransition.resolve(
      reduceMotion: reduceMotion,
      reduceTransparency: reduceTransparency,
      increaseContrast: colorSchemeContrast == .increased,
      differentiateWithoutColor: differentiateWithoutColor,
      backgroundOpacity: content.appearance.backgroundOpacity
    )
  }

  private var expandedTopInset: CGFloat {
    guard content.isExpanded else {
      return 0
    }
    if case .notchAttached(let notchSize) = presentationStyle {
      return notchSize.height
    }
    return 0
  }

  private var surfaceBackgroundOpacity: Double {
    switch presentationStyle {
    case .notchAttached:
      1
    case .floatingCapsule:
      signatureTransition.backgroundOpacity
    }
  }

  private var surfaceShape: TopSurfaceShape {
    TopSurfaceShape(
      presentationStyle: presentationStyle,
      isExpanded: content.isExpanded
    )
  }

  private var contentAnimation: Animation {
    .easeInOut(duration: signatureTransition.duration)
  }

  private var shapeAnimation: Animation? {
    guard signatureTransition.animatesShape else {
      return nil
    }
    return .easeInOut(duration: signatureTransition.duration)
  }

  private var surfaceTransition: AnyTransition {
    .opacity
  }

  private var titleTransition: AnyTransition {
    guard signatureTransition.usesProgressiveTitleBlur else {
      return .opacity
    }
    return .asymmetric(
      insertion: .opacity,
      removal: .modifier(
        active: ProgressiveTitleBlurModifier(
          blurRadius: signatureTransition.outgoingTitleBlurRadius,
          opacity: 0
        ),
        identity: ProgressiveTitleBlurModifier(
          blurRadius: 0,
          opacity: 1
        )
      )
    )
  }

  @ViewBuilder
  private var focusMarker: some View {
    if content.isCurrentFocus {
      Capsule()
        .fill(.white)
        .frame(width: 15, height: 6)
        .accessibilityLabel("当前重点")
    } else {
      Text("\(content.position)")
        .font(.caption2.monospacedDigit().weight(.bold))
        .frame(width: 15, height: 15)
        .overlay {
          Capsule().stroke(
            .white,
            lineWidth: signatureTransition.usesHighContrastMarkers ? 1.5 : 1
          )
        }
        .accessibilityLabel("次要重点，第 \(content.position) 项")
    }
  }
}

private struct ProgressiveTitleBlurModifier: ViewModifier {
  let blurRadius: Double
  let opacity: Double

  func body(content: Content) -> some View {
    content
      .blur(radius: blurRadius)
      .opacity(opacity)
  }
}
