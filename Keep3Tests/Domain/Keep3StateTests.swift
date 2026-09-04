import XCTest

@testable import Keep3

final class Keep3StateTests: XCTestCase {
  func testFocusItemAcceptsDocumentedBoundaryLengthsAndTrimsTitle() throws {
    let title = String(repeating: "👨‍👩‍👧‍👦", count: 60)
    let details = String(repeating: "详", count: 500)
    let subitem = String(repeating: "项", count: 120)

    let item = try FocusItem(
      title: " \n\(title)\t ",
      details: details,
      subitems: Array(repeating: subitem, count: 8)
    )

    XCTAssertEqual(item.title, title)
    XCTAssertEqual(item.details, details)
    XCTAssertEqual(item.subitems, Array(repeating: subitem, count: 8))
  }

  func testFocusItemRejectsBlankTitle() {
    XCTAssertThrowsError(try FocusItem(title: " \n\t ")) { error in
      XCTAssertEqual(error as? FocusItem.ValidationError, .emptyTitle)
    }
  }

  func testFocusItemRejectsTitleOverSixtyUserPerceivedCharacters() {
    let title = String(repeating: "👨‍👩‍👧‍👦", count: 61)

    XCTAssertThrowsError(try FocusItem(title: title)) { error in
      XCTAssertEqual(error as? FocusItem.ValidationError, .titleTooLong)
    }
  }

  func testFocusItemRejectsDetailsOverFiveHundredCharacters() {
    let details = String(repeating: "详", count: 501)

    XCTAssertThrowsError(try FocusItem(title: "重点", details: details)) { error in
      XCTAssertEqual(error as? FocusItem.ValidationError, .detailsTooLong)
    }
  }

  func testFocusItemRejectsMoreThanEightSubitems() {
    XCTAssertThrowsError(
      try FocusItem(
        title: "重点",
        subitems: Array(repeating: "说明", count: 9)
      )
    ) { error in
      XCTAssertEqual(error as? FocusItem.ValidationError, .tooManySubitems)
    }
  }

  func testFocusItemRejectsSubitemOverOneHundredTwentyCharacters() {
    let subitem = String(repeating: "项", count: 121)

    XCTAssertThrowsError(
      try FocusItem(title: "重点", subitems: [subitem])
    ) { error in
      XCTAssertEqual(error as? FocusItem.ValidationError, .subitemTooLong(index: 0))
    }
  }

  func testStateAcceptsZeroToThreeItemsAndRejectsFourthWithoutMutation() throws {
    var state = Keep3State()
    let items = try [
      FocusItem(title: "一"),
      FocusItem(title: "二"),
      FocusItem(title: "三"),
      FocusItem(title: "四"),
    ]

    try state.add(items[0])
    try state.add(items[1])
    try state.add(items[2])

    XCTAssertEqual(state.items, Array(items.prefix(3)))
    XCTAssertThrowsError(try state.add(items[3])) { error in
      XCTAssertEqual(error as? Keep3State.MutationError, .itemLimitReached)
    }
    XCTAssertEqual(state.items, Array(items.prefix(3)))
  }

  func testFirstItemBecomesCurrentFocus() throws {
    var state = Keep3State()
    let first = try FocusItem(title: "当前重点")

    try state.add(first)

    XCTAssertEqual(state.currentFocusID, first.id)
    XCTAssertEqual(state.currentFocus, first)
  }

  func testRemovingCurrentFocusSelectsFirstRemainingItem() throws {
    let first = try FocusItem(title: "一")
    let second = try FocusItem(title: "二")
    let third = try FocusItem(title: "三")
    var state = Keep3State()
    try state.add(first)
    try state.add(second)
    try state.add(third)
    try state.setCurrentFocus(id: second.id)

    try state.remove(id: second.id)

    XCTAssertEqual(state.items, [first, third])
    XCTAssertEqual(state.currentFocusID, first.id)
  }

  func testRemovingFinalItemClearsCurrentFocus() throws {
    let item = try FocusItem(title: "唯一重点")
    var state = Keep3State()
    try state.add(item)

    try state.remove(id: item.id)

    XCTAssertTrue(state.items.isEmpty)
    XCTAssertNil(state.currentFocusID)
    XCTAssertNil(state.currentFocus)
  }

  func testArchivingCurrentFocusCreatesNewestSnapshotAndSelectsFirstRemaining()
    throws
  {
    let first = try FocusItem(title: "一")
    let second = try FocusItem(
      title: "二",
      details: "说明",
      subitems: ["补充"]
    )
    let third = try FocusItem(title: "三")
    let archivedAt = Date(timeIntervalSince1970: 1_725_408_000)
    var state = try Keep3State(
      items: [first, second, third],
      currentFocusID: second.id
    )

    let archived = try state.archive(id: second.id, at: archivedAt)

    XCTAssertEqual(state.items, [first, third])
    XCTAssertEqual(state.currentFocusID, first.id)
    XCTAssertEqual(state.archivedItems, [archived])
    XCTAssertEqual(archived.item, second)
    XCTAssertEqual(archived.archivedAt, archivedAt)
  }

  func testArchivingSecondaryPreservesFocusAndFinalArchiveClearsIt() throws {
    let first = try FocusItem(title: "一")
    let second = try FocusItem(title: "二")
    var state = try Keep3State(
      items: [first, second],
      currentFocusID: first.id
    )

    try state.archive(
      id: second.id,
      at: Date(timeIntervalSince1970: 200)
    )
    XCTAssertEqual(state.currentFocusID, first.id)

    try state.archive(
      id: first.id,
      at: Date(timeIntervalSince1970: 300)
    )
    XCTAssertTrue(state.items.isEmpty)
    XCTAssertNil(state.currentFocusID)
    XCTAssertEqual(state.archivedItems.map(\.item.title), ["一", "二"])
  }

  func testUndoArchiveRestoresIdentityPositionAndFormerFocus() throws {
    let first = try FocusItem(title: "一")
    let second = try FocusItem(title: "二")
    let third = try FocusItem(title: "三")
    var state = try Keep3State(
      items: [first, second, third],
      currentFocusID: second.id
    )
    let archived = try state.archive(id: second.id, at: Date())

    try state.undoArchive(
      id: archived.id,
      to: 1,
      restoringCurrentFocus: true
    )

    XCTAssertEqual(state.items, [first, second, third])
    XCTAssertEqual(state.currentFocusID, second.id)
    XCTAssertTrue(state.archivedItems.isEmpty)
  }

  func testPermanentArchiveDeletionDoesNotChangeActiveFocus() throws {
    let active = try FocusItem(title: "当前")
    let archived = ArchivedFocusItem(
      item: try FocusItem(title: "历史"),
      archivedAt: Date()
    )
    var state = try Keep3State(
      items: [active],
      currentFocusID: active.id,
      archivedItems: [archived]
    )

    try state.removeArchived(id: archived.id)

    XCTAssertTrue(state.archivedItems.isEmpty)
    XCTAssertEqual(state.currentFocusID, active.id)
  }

  func testStateRejectsDuplicateIdentityAcrossActiveAndArchive() throws {
    let item = try FocusItem(title: "重点")
    let archived = ArchivedFocusItem(item: item, archivedAt: Date())

    XCTAssertThrowsError(
      try Keep3State(
        items: [item],
        currentFocusID: item.id,
        archivedItems: [archived]
      )
    ) { error in
      XCTAssertEqual(error as? Keep3State.ValidationError, .duplicateItemID)
    }
  }

  func testAddingRejectsIdentityAlreadyPresentInArchive() throws {
    let item = try FocusItem(title: "历史")
    let archived = ArchivedFocusItem(item: item, archivedAt: Date())
    var state = try Keep3State(
      items: [],
      currentFocusID: nil,
      archivedItems: [archived]
    )

    XCTAssertThrowsError(try state.add(item)) { error in
      XCTAssertEqual(error as? Keep3State.MutationError, .duplicateItemID)
    }
    XCTAssertTrue(state.items.isEmpty)
  }

  func testClockRollbackKeepsArchiveHistorySortedAndPersistable() throws {
    let first = try FocusItem(title: "先归档")
    let second = try FocusItem(title: "后归档但时钟较早")
    var state = try Keep3State(
      items: [first, second],
      currentFocusID: first.id
    )

    try state.archive(id: first.id, at: Date(timeIntervalSince1970: 200))
    try state.archive(id: second.id, at: Date(timeIntervalSince1970: 100))

    XCTAssertEqual(state.archivedItems.map(\.item.title), ["先归档", "后归档但时钟较早"])
    XCTAssertNoThrow(
      try Keep3State(
        items: state.items,
        currentFocusID: state.currentFocusID,
        archivedItems: state.archivedItems
      )
    )
  }

  func testStateRejectsArchiveHistoryThatIsNotNewestFirst() throws {
    let newer = ArchivedFocusItem(
      item: try FocusItem(title: "较新"),
      archivedAt: Date(timeIntervalSince1970: 200)
    )
    let older = ArchivedFocusItem(
      item: try FocusItem(title: "较早"),
      archivedAt: Date(timeIntervalSince1970: 100)
    )

    XCTAssertThrowsError(
      try Keep3State(
        items: [],
        currentFocusID: nil,
        archivedItems: [older, newer]
      )
    ) { error in
      XCTAssertEqual(
        error as? Keep3State.ValidationError,
        .archiveOrderInvalid
      )
    }
  }

  func testReorderingPreservesIdentityAndCurrentFocus() throws {
    let first = try FocusItem(title: "一")
    let second = try FocusItem(title: "二")
    let third = try FocusItem(title: "三")
    var state = Keep3State()
    try state.add(first)
    try state.add(second)
    try state.add(third)
    try state.setCurrentFocus(id: second.id)

    try state.moveItem(id: third.id, to: 0)

    XCTAssertEqual(state.items.map(\.id), [third.id, first.id, second.id])
    XCTAssertEqual(state.items.map(\.title), ["三", "一", "二"])
    XCTAssertEqual(state.currentFocusID, second.id)
  }

  func testUpdatingItemPreservesIdentityOrderAndCurrentFocus() throws {
    let first = try FocusItem(title: "一")
    let second = try FocusItem(title: "二")
    var state = Keep3State()
    try state.add(first)
    try state.add(second)

    try state.updateItem(
      id: first.id,
      title: "更新后",
      details: "相关说明",
      subitems: ["说明一", "说明二"]
    )

    XCTAssertEqual(state.items.map(\.id), [first.id, second.id])
    XCTAssertEqual(state.currentFocusID, first.id)
    XCTAssertEqual(state.items[0].title, "更新后")
    XCTAssertEqual(state.items[0].details, "相关说明")
    XCTAssertEqual(state.items[0].subitems, ["说明一", "说明二"])
  }

  func testInvalidUpdateLeavesStateUnchanged() throws {
    let item = try FocusItem(title: "有效重点")
    var state = Keep3State()
    try state.add(item)
    let originalState = state

    XCTAssertThrowsError(
      try state.updateItem(
        id: item.id,
        title: String(repeating: "项", count: 61),
        details: "",
        subitems: []
      )
    )
    XCTAssertEqual(state, originalState)
  }

  func testNonemptyStateRejectsMissingOrUnknownCurrentFocus() throws {
    let item = try FocusItem(title: "重点")

    XCTAssertThrowsError(
      try Keep3State(items: [item], currentFocusID: nil)
    ) { error in
      XCTAssertEqual(error as? Keep3State.ValidationError, .missingCurrentFocus)
    }
    XCTAssertThrowsError(
      try Keep3State(items: [item], currentFocusID: UUID())
    ) { error in
      XCTAssertEqual(error as? Keep3State.ValidationError, .unknownCurrentFocus)
    }
  }
}
