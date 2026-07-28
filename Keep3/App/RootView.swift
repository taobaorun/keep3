import SwiftUI

enum MainWindowDestination: String, Hashable {
  case editor
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
  @ObservedObject var destinationState: MainWindowDestinationState

  var body: some View {
    TabView(selection: $destinationState.destination) {
      EditorView(model: model)
        .tabItem {
          Label("重点", systemImage: "scope")
        }
        .tag(MainWindowDestination.editor)

      SettingsView(
        preferences: preferences,
        mediaPreferences: mediaPreferences,
        calendarPreferences: calendarPreferences,
        calendarCoordinator: calendarCoordinator,
        launchAtLoginController: launchAtLoginController
      )
      .tabItem {
        Label("设置", systemImage: "gearshape")
      }
      .tag(MainWindowDestination.settings)
    }
  }
}
