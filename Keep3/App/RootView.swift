import SwiftUI

enum InteractionMotion {
  static let pressInDuration: TimeInterval = 0.1
  static let pressOutDuration: TimeInterval = 0.16
  static let transientEntranceDuration: TimeInterval = 0.18
  static let transientExitDuration: TimeInterval = 0.12
  static let stateChangeDuration: TimeInterval = 0.16
  static let reducedMotionDuration: TimeInterval = 0.12

  static func strongEaseOut(duration: TimeInterval) -> Animation {
    .timingCurve(0.23, 1, 0.32, 1, duration: duration)
  }
}

enum MainWindowDestination: Hashable {
  case editor
  case history
  case settings
}

@MainActor
final class MainWindowDestinationState: ObservableObject {
  @Published var destination: MainWindowDestination = .editor
}

struct RootView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var preferences: AppPreferences
  @ObservedObject var mediaPreferences: MediaPreferences
  @ObservedObject var calendarPreferences: CalendarPreferences
  @ObservedObject var calendarCoordinator: CalendarSessionCoordinator
  @ObservedObject var launchAtLoginController: LaunchAtLoginController
  @ObservedObject var updateController: SparkleUpdateController
  @ObservedObject var destinationState: MainWindowDestinationState

  var body: some View {
    TabView(selection: $destinationState.destination) {
      EditorView(model: model)
        .tabItem {
          Label("重点", systemImage: "scope")
        }
        .tag(MainWindowDestination.editor)

      HistoryView(model: model)
        .tabItem {
          Label("历史", systemImage: "archivebox")
        }
        .tag(MainWindowDestination.history)

      SettingsView(
        preferences: preferences,
        mediaPreferences: mediaPreferences,
        calendarPreferences: calendarPreferences,
        calendarCoordinator: calendarCoordinator,
        launchAtLoginController: launchAtLoginController,
        updateController: updateController
      )
      .tabItem {
        Label("设置", systemImage: "gearshape")
      }
      .tag(MainWindowDestination.settings)
    }
    .tint(Color("AccentColor"))
  }
}
