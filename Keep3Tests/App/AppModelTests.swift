import XCTest

@testable import Keep3

@MainActor
final class AppModelTests: XCTestCase {
  func testAddingThreeItemsSelectsNewestForEditingAndKeepsFirstCurrent() throws {
    let model = AppModel()

    let firstID = try XCTUnwrap(model.addItem(title: "一"))
    _ = try XCTUnwrap(model.addItem(title: "二"))
    let thirdID = try XCTUnwrap(model.addItem(title: "三"))

    XCTAssertEqual(model.state.items.map(\.title), ["一", "二", "三"])
    XCTAssertEqual(model.state.currentFocusID, firstID)
    XCTAssertEqual(model.selectedItemID, thirdID)
    XCTAssertNil(model.editorMessage)
  }

  func testFourthItemIsRejectedWithoutChangingState() throws {
    let model = AppModel()
    _ = model.addItem(title: "一")
    _ = model.addItem(title: "二")
    _ = model.addItem(title: "三")
    let originalState = model.state

    let fourthID = model.addItem(title: "四")

    XCTAssertNil(fourthID)
    XCTAssertEqual(model.state, originalState)
    XCTAssertNotNil(model.editorMessage)
  }

  func testEditingItemUpdatesAllPlainTextContentAndPreservesIdentity() throws {
    let model = AppModel()
    let id = try XCTUnwrap(model.addItem(title: "原来的重点"))

    model.updateItem(
      id: id,
      title: "新的重点",
      details: "为什么重要",
      subitems: ["说明一", "说明二"]
    )

    let item = try XCTUnwrap(model.state.items.first)
    XCTAssertEqual(item.id, id)
    XCTAssertEqual(item.title, "新的重点")
    XCTAssertEqual(item.details, "为什么重要")
    XCTAssertEqual(item.subitems, ["说明一", "说明二"])
    XCTAssertNil(model.editorMessage)
  }

  func testInvalidEditKeepsLastValidState() throws {
    let model = AppModel()
    let id = try XCTUnwrap(model.addItem(title: "有效重点"))
    let originalState = model.state

    model.updateItem(
      id: id,
      title: String(repeating: "项", count: 61),
      details: "",
      subitems: []
    )

    XCTAssertEqual(model.state, originalState)
    XCTAssertNotNil(model.editorMessage)
  }

  func testSelectingCurrentFocusPublishesTopSurfaceState() throws {
    let model = AppModel()
    _ = model.addItem(title: "一")
    let secondID = try XCTUnwrap(model.addItem(title: "二"))
    var observedTitles: [String?] = []
    model.onStateChange = { observedTitles.append($0.currentFocus?.title) }

    model.setCurrentFocus(id: secondID)

    XCTAssertEqual(model.state.currentFocusID, secondID)
    XCTAssertEqual(observedTitles, ["二"])
  }

  func testRemovingCurrentFocusSelectsFirstRemainingForFocusAndEditing() throws {
    let model = AppModel()
    let firstID = try XCTUnwrap(model.addItem(title: "一"))
    let secondID = try XCTUnwrap(model.addItem(title: "二"))
    model.setCurrentFocus(id: secondID)

    model.removeItem(id: secondID)

    XCTAssertEqual(model.state.items.map(\.id), [firstID])
    XCTAssertEqual(model.state.currentFocusID, firstID)
    XCTAssertEqual(model.selectedItemID, firstID)
  }

  func testReorderingChangesDisplayOrderWithoutChangingCurrentFocus() throws {
    let model = AppModel()
    let firstID = try XCTUnwrap(model.addItem(title: "一"))
    _ = model.addItem(title: "二")
    let thirdID = try XCTUnwrap(model.addItem(title: "三"))

    model.moveItem(id: thirdID, to: 0)

    XCTAssertEqual(model.state.items.map(\.title), ["三", "一", "二"])
    XCTAssertEqual(model.state.currentFocusID, firstID)
  }

  func testStoreLoadsAtInitializationAndAutosavesValidChanges() throws {
    let storedItem = try FocusItem(title: "已保存")
    var storedState = Keep3State()
    try storedState.add(storedItem)
    let store = RecordingStateStore(stateToLoad: storedState)

    let model = AppModel(stateStore: store)
    _ = model.addItem(title: "新增")

    XCTAssertEqual(model.state.items.map(\.title), ["已保存", "新增"])
    XCTAssertEqual(store.savedStates, [model.state])
    XCTAssertNil(model.persistenceMessage)
  }
}

private final class RecordingStateStore: StateStore {
  let stateToLoad: Keep3State
  private(set) var savedStates: [Keep3State] = []

  init(stateToLoad: Keep3State) {
    self.stateToLoad = stateToLoad
  }

  func load() throws -> StateLoadResult {
    StateLoadResult(state: stateToLoad)
  }

  func save(_ state: Keep3State) throws {
    savedStates.append(state)
  }
}
