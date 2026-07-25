import XCTest

@testable import Keep3

@MainActor
final class LaunchAtLoginTests: XCTestCase {
  func testInitialStateReflectsServiceRegistration() {
    let enabled = LaunchAtLoginController(
      service: FakeLaunchAtLoginService(status: .enabled)
    )
    XCTAssertTrue(enabled.isOn)
    XCTAssertNil(enabled.message)

    let disabled = LaunchAtLoginController(
      service: FakeLaunchAtLoginService(status: .notRegistered)
    )
    XCTAssertFalse(disabled.isOn)
    XCTAssertNil(disabled.message)
  }

  func testRegistrationRequiringApprovalKeepsRequestVisible() {
    let service = FakeLaunchAtLoginService(status: .notRegistered)
    service.statusAfterRegistration = .requiresApproval
    let controller = LaunchAtLoginController(service: service)

    controller.setEnabled(true)

    XCTAssertEqual(service.registerCount, 1)
    XCTAssertTrue(controller.isOn)
    XCTAssertEqual(
      controller.message,
      "请在“系统设置 > 通用 > 登录项”中允许 Keep3。"
    )

    service.status = .enabled
    controller.refresh()
    XCTAssertTrue(controller.isOn)
    XCTAssertNil(controller.message)
  }

  func testUnregisteringUpdatesTheReflectedState() {
    let service = FakeLaunchAtLoginService(status: .enabled)
    service.statusAfterUnregistration = .notRegistered
    let controller = LaunchAtLoginController(service: service)

    controller.setEnabled(false)

    XCTAssertEqual(service.unregisterCount, 1)
    XCTAssertFalse(controller.isOn)
    XCTAssertNil(controller.message)
  }

  func testRegistrationFailureDoesNotClaimTheSettingChanged() {
    let service = FakeLaunchAtLoginService(status: .notRegistered)
    service.registrationError = TestError.registrationFailed
    let controller = LaunchAtLoginController(service: service)

    controller.setEnabled(true)

    XCTAssertFalse(controller.isOn)
    XCTAssertEqual(controller.message, "无法开启登录时启动，请稍后重试。")
  }
}

private enum TestError: Error {
  case registrationFailed
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
  var status: LaunchAtLoginRegistrationStatus
  var statusAfterRegistration: LaunchAtLoginRegistrationStatus = .enabled
  var statusAfterUnregistration: LaunchAtLoginRegistrationStatus = .notRegistered
  var registrationError: Error?
  var unregistrationError: Error?
  private(set) var registerCount = 0
  private(set) var unregisterCount = 0

  init(status: LaunchAtLoginRegistrationStatus) {
    self.status = status
  }

  func register() throws {
    registerCount += 1
    if let registrationError {
      throw registrationError
    }
    status = statusAfterRegistration
  }

  func unregister() throws {
    unregisterCount += 1
    if let unregistrationError {
      throw unregistrationError
    }
    status = statusAfterUnregistration
  }
}
