import XCTest

@testable import Keep3

final class MediaRemoteSymbolsTests: XCTestCase {
  func testMissingMandatorySymbolDisablesTheWholeAdapter() {
    let report = MediaRemoteSymbolResolver.resolve(using: { name in
      name == "MRMediaRemoteGetNowPlayingClient" ? UnsafeMutableRawPointer(bitPattern: 1) : nil
    })

    XCTAssertEqual(report.status, .unavailable)
    XCTAssertEqual(report.missingMandatorySymbols.count, 2)
    XCTAssertTrue(report.optionalCapabilities.isEmpty)
  }

  func testMissingOptionalSymbolRetainsBaselineCapabilities() {
    let report = MediaRemoteSymbolResolver.resolve(using: { name in
      MediaRemoteSymbolResolver.mandatorySymbols.contains(name)
        ? UnsafeMutableRawPointer(bitPattern: 1)
        : nil
    })

    XCTAssertEqual(report.status, .available)
    XCTAssertEqual(report.optionalCapabilities, [])
    XCTAssertEqual(report.missingOptionalSymbols.count, 4)
  }
}
