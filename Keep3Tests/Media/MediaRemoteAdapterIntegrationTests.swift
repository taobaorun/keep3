import XCTest

@testable import Keep3

final class MediaRemoteAdapterIntegrationTests: XCTestCase {
  func testEmbeddedAlcoveStyleHelperStartsAndStopsCleanly() async {
    let adapter = MediaRemoteAdapter()

    let report = await adapter.start()
    await adapter.stop()

    XCTAssertEqual(
      report.status,
      .available,
      "Missing mandatory symbols: \(report.missingMandatorySymbols)"
    )
  }
}
