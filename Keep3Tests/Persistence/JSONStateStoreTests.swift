import XCTest

@testable import Keep3

final class JSONStateStoreTests: XCTestCase {
  private var directoryURL: URL!
  private var stateFileURL: URL!

  override func setUpWithError() throws {
    directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    stateFileURL = directoryURL.appendingPathComponent("state.json")
  }

  override func tearDownWithError() throws {
    if let directoryURL {
      try FileManager.default.removeItem(at: directoryURL)
    }
  }

  func testMissingFileLoadsEmptyStateWithoutRecoveryMessage() throws {
    let store = makeStore()

    let result = try store.load()

    XCTAssertEqual(result.state, Keep3State())
    XCTAssertNil(result.recoveryFileURL)
    XCTAssertNil(result.message)
  }

  func testValidStateRoundTripsAndCanBeAtomicallyReplaced() throws {
    let store = makeStore()
    let first = try FocusItem(
      title: "一",
      details: "说明",
      subitems: ["补充"]
    )
    let second = try FocusItem(title: "二")
    var state = Keep3State()
    try state.add(first)
    try state.add(second)
    try state.setCurrentFocus(id: second.id)

    try store.save(state)
    var updatedState = state
    try updatedState.updateItem(
      id: second.id,
      title: "更新后的二",
      details: "",
      subitems: []
    )
    try store.save(updatedState)

    let loaded = try store.load()
    XCTAssertEqual(loaded.state, updatedState)
    XCTAssertNil(loaded.message)
  }

  func testSchemaOneMigratesLosslesslyWithEmptyArchiveAndSavesSchemaTwo()
    throws
  {
    let id = UUID()
    let json = """
      {
        "schemaVersion": 1,
        "items": [
          {"id":"\(id.uuidString)","title":"原有重点","details":"说明","subitems":["补充"]}
        ],
        "currentFocusID": "\(id.uuidString)"
      }
      """
    try Data(json.utf8).write(to: stateFileURL)
    let store = makeStore()

    let migrated = try store.load().state

    XCTAssertEqual(migrated.items.map(\.title), ["原有重点"])
    XCTAssertEqual(migrated.currentFocusID, id)
    XCTAssertTrue(migrated.archivedItems.isEmpty)

    try store.save(migrated)
    let saved =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: stateFileURL)
      ) as? [String: Any]
    XCTAssertEqual(saved?["schemaVersion"] as? Int, 2)
  }

  func testSchemaTwoRoundTripsArchiveHistory() throws {
    let current = try FocusItem(title: "当前")
    let old = ArchivedFocusItem(
      item: try FocusItem(
        title: "过去",
        details: "历史说明",
        subitems: ["一", "二"]
      ),
      archivedAt: Date(timeIntervalSince1970: 1_725_408_000)
    )
    let state = try Keep3State(
      items: [current],
      currentFocusID: current.id,
      archivedItems: [old]
    )
    let store = makeStore()

    try store.save(state)

    XCTAssertEqual(try store.load().state, state)
  }

  func testSchemaTwoDuplicateIdentityIsPreservedForRecovery() throws {
    let id = UUID()
    let json = """
      {
        "schemaVersion": 2,
        "items": [
          {"id":"\(id.uuidString)","title":"当前","details":"","subitems":[]}
        ],
        "currentFocusID": "\(id.uuidString)",
        "archivedItems": [
          {
            "item":{"id":"\(id.uuidString)","title":"历史","details":"","subitems":[]},
            "archivedAt":0
          }
        ]
      }
      """
    try Data(json.utf8).write(to: stateFileURL)
    let store = makeStore()

    let result = try store.load()

    XCTAssertEqual(result.state, Keep3State())
    XCTAssertNotNil(result.recoveryFileURL)
  }

  func testMalformedJSONIsMovedAsideAndLoadsEmptyState() throws {
    let originalData = Data("{ definitely-not-json".utf8)
    try originalData.write(to: stateFileURL)
    let store = makeStore()

    let result = try store.load()

    let recoveryURL = try XCTUnwrap(result.recoveryFileURL)
    XCTAssertEqual(result.state, Keep3State())
    XCTAssertNotNil(result.message)
    XCTAssertFalse(FileManager.default.fileExists(atPath: stateFileURL.path))
    XCTAssertEqual(try Data(contentsOf: recoveryURL), originalData)
  }

  func testMoreThanThreeStoredItemsAreRecoveredAsInvalid() throws {
    let ids = (0..<4).map { _ in UUID() }
    let itemJSON = zip(ids, ["一", "二", "三", "四"])
      .map { id, title in
        """
        {"id":"\(id.uuidString)","title":"\(title)","details":"","subitems":[]}
        """
      }
      .joined(separator: ",")
    let json = """
      {
        "schemaVersion": 1,
        "items": [\(itemJSON)],
        "currentFocusID": "\(ids[0].uuidString)"
      }
      """
    try Data(json.utf8).write(to: stateFileURL)
    let store = makeStore()

    let result = try store.load()

    XCTAssertEqual(result.state, Keep3State())
    XCTAssertNotNil(result.recoveryFileURL)
    XCTAssertNotNil(result.message)
  }

  func testInvalidStoredItemContentIsRecoveredAsInvalid() throws {
    let id = UUID()
    let title = String(repeating: "项", count: 61)
    let json = """
      {
        "schemaVersion": 1,
        "items": [
          {"id":"\(id.uuidString)","title":"\(title)","details":"","subitems":[]}
        ],
        "currentFocusID": "\(id.uuidString)"
      }
      """
    try Data(json.utf8).write(to: stateFileURL)
    let store = makeStore()

    let result = try store.load()

    XCTAssertEqual(result.state, Keep3State())
    XCTAssertNotNil(result.recoveryFileURL)
  }

  func testUnsupportedSchemaIsPreservedForRecovery() throws {
    let json = """
      {"schemaVersion":99,"items":[],"currentFocusID":null}
      """
    try Data(json.utf8).write(to: stateFileURL)
    let store = makeStore()

    let result = try store.load()

    XCTAssertEqual(result.state, Keep3State())
    XCTAssertNotNil(result.recoveryFileURL)
    XCTAssertNotNil(result.message)
  }

  private func makeStore() -> JSONStateStore {
    JSONStateStore(
      fileURL: stateFileURL,
      recoveryFileName: { "state.corrupt-test.json" }
    )
  }
}
