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
