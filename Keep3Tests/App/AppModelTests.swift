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

  func testArchivingPublishesSnapshotAndOffersOneUndo() throws {
    let archivedAt = Date(timeIntervalSince1970: 1_725_408_000)
    let model = AppModel(now: { archivedAt })
    let firstID = try XCTUnwrap(model.addItem(title: "一"))
    let secondID = try XCTUnwrap(model.addItem(title: "二"))
    model.setCurrentFocus(id: secondID)

    model.archiveItem(id: secondID)

    XCTAssertEqual(model.state.items.map(\.id), [firstID])
    XCTAssertEqual(model.state.currentFocusID, firstID)
    XCTAssertEqual(model.state.archivedItems.first?.id, secondID)
    XCTAssertEqual(model.state.archivedItems.first?.archivedAt, archivedAt)
    XCTAssertEqual(model.pendingArchiveUndo?.itemTitle, "二")
  }

  func testUndoArchiveRestoresSameItemAtOriginalPositionAndFocusOnce() throws {
    let model = AppModel()
    let firstID = try XCTUnwrap(model.addItem(title: "一"))
    let secondID = try XCTUnwrap(model.addItem(title: "二"))
    _ = try XCTUnwrap(model.addItem(title: "三"))
    model.setCurrentFocus(id: secondID)
    model.archiveItem(id: secondID)
    let operationID = try XCTUnwrap(model.pendingArchiveUndo?.operationID)

    model.undoArchive(operationID: operationID)

    XCTAssertEqual(model.state.items.map(\.title), ["一", "二", "三"])
    XCTAssertEqual(model.state.items[1].id, secondID)
    XCTAssertEqual(model.state.currentFocusID, secondID)
    XCTAssertEqual(model.selectedItemID, secondID)
    XCTAssertTrue(model.state.archivedItems.isEmpty)
    XCTAssertNil(model.pendingArchiveUndo)

    let restoredState = model.state
    model.undoArchive(operationID: operationID)
    XCTAssertEqual(model.state, restoredState)
    XCTAssertEqual(model.editorMessage, "这次归档已无法撤销。")
    XCTAssertEqual(model.state.items.first?.id, firstID)
  }

  func testAnotherContentMutationInvalidatesArchiveUndo() throws {
    let model = AppModel()
    let id = try XCTUnwrap(model.addItem(title: "一"))
    model.archiveItem(id: id)
    let operationID = try XCTUnwrap(model.pendingArchiveUndo?.operationID)
    XCTAssertNotNil(model.pendingArchiveUndo)

    _ = model.addItem(title: "新的重点")

    XCTAssertNil(model.pendingArchiveUndo)
    let stateAfterMutation = model.state
    model.undoArchive(operationID: operationID)
    XCTAssertEqual(model.state, stateAfterMutation)
  }

  func testDismissingUndoDoesNotMutatePersistedArchive() throws {
    let model = AppModel()
    let id = try XCTUnwrap(model.addItem(title: "历史"))
    model.archiveItem(id: id)
    let archivedState = model.state

    let operationID = try XCTUnwrap(model.pendingArchiveUndo?.operationID)
    model.dismissArchiveUndo(operationID: operationID)

    XCTAssertNil(model.pendingArchiveUndo)
    XCTAssertEqual(model.state, archivedState)
  }

  func testArchiveUndoExpiresFromModelTimerWithoutViewLifetime() throws {
    let scheduler = ManualAppTimerScheduler()
    let model = AppModel(archiveUndoScheduler: scheduler)
    let id = try XCTUnwrap(model.addItem(title: "历史"))

    model.archiveItem(id: id)

    XCTAssertEqual(scheduler.activeDelays, [8])
    XCTAssertNotNil(model.pendingArchiveUndo)
    scheduler.fireNext()
    XCTAssertNil(model.pendingArchiveUndo)
    XCTAssertEqual(model.state.archivedItems.map(\.id), [id])
  }

  func testStaleUndoExpiryCannotDismissANewerArchive() throws {
    let scheduler = ManualAppTimerScheduler()
    let model = AppModel(archiveUndoScheduler: scheduler)
    let firstID = try XCTUnwrap(model.addItem(title: "一"))
    let secondID = try XCTUnwrap(model.addItem(title: "二"))
    model.archiveItem(id: firstID)
    model.archiveItem(id: secondID)

    scheduler.fire(at: 0, includingCancelled: true)
    XCTAssertEqual(model.pendingArchiveUndo?.archiveID, secondID)

    scheduler.fire(at: 1, includingCancelled: true)
    XCTAssertNil(model.pendingArchiveUndo)
  }

  func testStaleExpiryCannotDismissSameItemAfterUndoAndRearchive() throws {
    let scheduler = ManualAppTimerScheduler()
    let model = AppModel(archiveUndoScheduler: scheduler)
    let itemID = try XCTUnwrap(model.addItem(title: "同一件事"))
    model.archiveItem(id: itemID)
    let firstOperationID = try XCTUnwrap(
      model.pendingArchiveUndo?.operationID
    )
    model.undoArchive(operationID: firstOperationID)
    model.archiveItem(id: itemID)
    let secondOperationID = try XCTUnwrap(
      model.pendingArchiveUndo?.operationID
    )
    XCTAssertNotEqual(firstOperationID, secondOperationID)

    let stateBeforeStaleUndo = model.state
    model.undoArchive(operationID: firstOperationID)
    XCTAssertEqual(model.state, stateBeforeStaleUndo)
    XCTAssertEqual(
      model.pendingArchiveUndo?.operationID,
      secondOperationID
    )

    scheduler.fire(at: 0, includingCancelled: true)
    XCTAssertEqual(
      model.pendingArchiveUndo?.operationID,
      secondOperationID
    )

    scheduler.fire(at: 1, includingCancelled: true)
    XCTAssertNil(model.pendingArchiveUndo)
  }

  func testArchiveAndUndoEachAutosaveTheCompleteState() throws {
    let first = try FocusItem(title: "一")
    let second = try FocusItem(title: "二")
    let initial = try Keep3State(
      items: [first, second],
      currentFocusID: second.id
    )
    let store = RecordingStateStore(stateToLoad: initial)
    let model = AppModel(
      stateStore: store,
      now: { Date(timeIntervalSince1970: 1_725_408_000) }
    )

    model.archiveItem(id: second.id)
    let operationID = try XCTUnwrap(model.pendingArchiveUndo?.operationID)
    model.undoArchive(operationID: operationID)

    XCTAssertEqual(store.savedStates.count, 2)
    XCTAssertEqual(store.savedStates[0].archivedItems.map(\.id), [second.id])
    XCTAssertEqual(store.savedStates[1], initial)
  }

  func testDeletingArchivedItemPreservesActiveFocus() throws {
    let active = try FocusItem(title: "当前")
    let archived = ArchivedFocusItem(
      item: try FocusItem(title: "历史"),
      archivedAt: Date()
    )
    let state = try Keep3State(
      items: [active],
      currentFocusID: active.id,
      archivedItems: [archived]
    )
    let model = AppModel(state: state)

    model.removeArchivedItem(id: archived.id)

    XCTAssertTrue(model.state.archivedItems.isEmpty)
    XCTAssertEqual(model.state.currentFocusID, active.id)
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

@MainActor
private final class ManualAppTimerScheduler: AppTimerScheduling {
  private final class Timer: AppTimerCancellation {
    let delay: TimeInterval
    let action: @MainActor () -> Void
    var isCancelled = false

    init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
      self.delay = delay
      self.action = action
    }

    func cancel() {
      isCancelled = true
    }
  }

  private var timers: [Timer] = []

  var activeDelays: [TimeInterval] {
    timers.filter { !$0.isCancelled }.map(\.delay)
  }

  func schedule(
    after delay: TimeInterval,
    action: @escaping @MainActor () -> Void
  ) -> any AppTimerCancellation {
    let timer = Timer(delay: delay, action: action)
    timers.append(timer)
    return timer
  }

  func fireNext() {
    guard let index = timers.firstIndex(where: { !$0.isCancelled }) else {
      return
    }
    fire(at: index, includingCancelled: false)
  }

  func fire(at index: Int, includingCancelled: Bool) {
    let timer = timers[index]
    guard includingCancelled || !timer.isCancelled else {
      return
    }
    timer.isCancelled = true
    timer.action()
  }
}
