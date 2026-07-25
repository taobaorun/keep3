import ServiceManagement

enum LaunchAtLoginRegistrationStatus: Equatable, Sendable {
  case notRegistered
  case enabled
  case requiresApproval
  case notFound
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
  var status: LaunchAtLoginRegistrationStatus { get }
  func register() throws
  func unregister() throws
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
  @Published private(set) var isOn = false
  @Published private(set) var message: String?

  private let service: any LaunchAtLoginServicing

  init(service: any LaunchAtLoginServicing) {
    self.service = service
    refresh()
  }

  static func live() -> LaunchAtLoginController {
    LaunchAtLoginController(service: SystemLaunchAtLoginService())
  }

  func setEnabled(_ shouldEnable: Bool) {
    guard isOn != shouldEnable else {
      refresh()
      return
    }

    do {
      if shouldEnable {
        try service.register()
      } else {
        try service.unregister()
      }
      refresh()
    } catch {
      updateFromService()
      message =
        shouldEnable
        ? "无法开启登录时启动，请稍后重试。"
        : "无法关闭登录时启动，请稍后重试。"
    }
  }

  func refresh() {
    updateFromService()
    switch service.status {
    case .requiresApproval:
      message = "请在“系统设置 > 通用 > 登录项”中允许 Keep3。"
    case .notFound:
      message = "当前构建无法使用登录时启动。"
    case .notRegistered, .enabled:
      message = nil
    }
  }

  private func updateFromService() {
    switch service.status {
    case .enabled, .requiresApproval:
      isOn = true
    case .notRegistered, .notFound:
      isOn = false
    }
  }
}

@MainActor
private final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
  private let service = SMAppService.mainApp

  var status: LaunchAtLoginRegistrationStatus {
    switch service.status {
    case .notRegistered:
      .notRegistered
    case .enabled:
      .enabled
    case .requiresApproval:
      .requiresApproval
    case .notFound:
      .notFound
    @unknown default:
      .notFound
    }
  }

  func register() throws {
    try service.register()
  }

  func unregister() throws {
    try service.unregister()
  }
}
