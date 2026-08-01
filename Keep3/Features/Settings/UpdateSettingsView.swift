import AppKit
import SwiftUI

struct UpdateSettingsView: View {
  @ObservedObject var updateController: SparkleUpdateController

  var body: some View {
    GroupBox("更新") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Button("检查更新…") {
            updateController.checkForUpdates()
          }
          .disabled(!updateController.canCheckForUpdates)
          .accessibilityIdentifier("settings.updates.checkNow")
          .accessibilityLabel("检查 Keep3 更新")

          Text(updateController.status.message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("settings.updates.status")
            .accessibilityLabel(
              "更新状态：\(updateController.status.message)"
            )
        }

        Toggle(
          "自动检查更新",
          isOn: Binding(
            get: { updateController.automaticallyChecksForUpdates },
            set: {
              updateController.setAutomaticallyChecksForUpdates($0)
            }
          )
        )
        .accessibilityIdentifier("settings.updates.automaticChecks")
        .accessibilityLabel("自动检查 Keep3 更新")

        Toggle(
          "自动下载更新",
          isOn: Binding(
            get: { updateController.automaticallyDownloadsUpdates },
            set: {
              updateController.setAutomaticallyDownloadsUpdates($0)
            }
          )
        )
        .disabled(!updateController.automaticallyChecksForUpdates)
        .accessibilityIdentifier("settings.updates.automaticDownloads")
        .accessibilityLabel("自动下载 Keep3 更新")

        if !updateController.automaticallyChecksForUpdates {
          Text("启用自动检查后，才能选择自动下载更新。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text("更新请求只包含版本检查和下载所需的信息，不会上传你的重点、媒体或日历内容。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .onChange(of: updateController.status) { _, status in
        NSAccessibility.post(
          element: NSApp as Any,
          notification: .announcementRequested,
          userInfo: [
            .announcement: status.message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
          ]
        )
      }
    }
  }
}
