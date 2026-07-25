import SwiftUI

struct RootView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var preferences: AppPreferences
  @ObservedObject var launchAtLoginController: LaunchAtLoginController

  var body: some View {
    TabView {
      EditorView(model: model)
        .tabItem {
          Label("重点", systemImage: "scope")
        }

      SettingsView(
        preferences: preferences,
        launchAtLoginController: launchAtLoginController
      )
      .tabItem {
        Label("设置", systemImage: "gearshape")
      }
    }
  }
}
