import SwiftUI

enum MainWindowDestination: Hashable {
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
          Text("Keep3")
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
        Image(systemName: "gearshape")
          .accessibilityLabel("设置")
      }
      .tag(MainWindowDestination.settings)
    }
  }
}
