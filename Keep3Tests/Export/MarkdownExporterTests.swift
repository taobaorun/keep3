import XCTest

@testable import Keep3

final class MarkdownExporterTests: XCTestCase {
  private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

  func testCompleteExportPreservesActiveAndNewestFirstArchiveOrder() throws {
    let first = try FocusItem(
      title: "当前 #重点",
      details: "第一行\n第二行",
      subitems: ["准备 *材料*", "确认 [范围]"]
    )
    let second = try FocusItem(title: "另一个重点")
    let newest = ArchivedFocusItem(
      item: try FocusItem(title: "最近归档"),
      archivedAt: Date(timeIntervalSince1970: 1_725_408_000)
    )
    let oldest = ArchivedFocusItem(
      item: try FocusItem(title: "更早归档"),
      archivedAt: Date(timeIntervalSince1970: 1_725_321_600)
    )
    let state = try Keep3State(
      items: [first, second],
      currentFocusID: first.id,
      archivedItems: [newest, oldest]
    )
    let exporter = MarkdownExporter(timeZone: shanghai)

    let output = exporter.complete(state: state)

    XCTAssertTrue(output.hasSuffix("\n"))
    XCTAssertTrue(output.contains("## 当前三件事"))
    XCTAssertTrue(output.contains("### 1（当前重点）"))
    XCTAssertTrue(output.contains("当前 \\#重点"))
    XCTAssertTrue(output.contains("第一行  \n第二行"))
    XCTAssertTrue(output.contains("- 准备 \\*材料\\*"))
    XCTAssertTrue(output.contains("- 确认 \\[范围\\]"))
    XCTAssertTrue(output.contains("2024-09-04 08:00:00 +08:00"))
    XCTAssertLessThan(
      try XCTUnwrap(output.range(of: "当前 \\#重点")?.lowerBound),
      try XCTUnwrap(output.range(of: "另一个重点")?.lowerBound)
    )
    XCTAssertLessThan(
      try XCTUnwrap(output.range(of: "最近归档")?.lowerBound),
      try XCTUnwrap(output.range(of: "更早归档")?.lowerBound)
    )
    XCTAssertEqual(state.items, [first, second])
    XCTAssertEqual(state.archivedItems, [newest, oldest])
  }

  func testCompleteExportRepresentsEmptyCollections() {
    let output = MarkdownExporter(timeZone: shanghai).complete(
      state: Keep3State()
    )

    XCTAssertTrue(output.contains("当前没有重要事项。"))
    XCTAssertTrue(output.contains("还没有归档记录。"))
  }

  func testSingleArchiveExportContainsOnlySelectedSnapshot() throws {
    let selected = ArchivedFocusItem(
      item: try FocusItem(
        title: "被选择的记录",
        details: "只读说明",
        subitems: ["上下文"]
      ),
      archivedAt: Date(timeIntervalSince1970: 1_725_408_000)
    )

    let output = MarkdownExporter(timeZone: shanghai).archivedItem(selected)

    XCTAssertTrue(output.contains("# Keep3 历史记录"))
    XCTAssertTrue(output.contains("被选择的记录"))
    XCTAssertTrue(output.contains("只读说明"))
    XCTAssertTrue(output.contains("- 上下文"))
    XCTAssertTrue(output.contains("2024-09-04 08:00:00 +08:00"))
    XCTAssertFalse(output.contains("当前三件事"))
  }

  func testExportEscapesEntitiesAndAllActiveMarkdownPunctuation() throws {
    let item = try FocusItem(title: "&copy; ~~原样~~ \"引号\"")
    var state = Keep3State()
    try state.add(item)

    let output = MarkdownExporter(timeZone: shanghai).complete(state: state)

    XCTAssertTrue(output.contains("\\&copy\\;"))
    XCTAssertTrue(output.contains("\\~\\~原样\\~\\~"))
    XCTAssertTrue(output.contains("\\\"引号\\\""))
  }

  func testExportNormalizesLFCRLFAndCRAsSingleLogicalLineBreaks() throws {
    let item = try FocusItem(
      title: "换行",
      details: "甲\n乙\r\n丙\r丁"
    )
    var state = Keep3State()
    try state.add(item)

    let output = MarkdownExporter(timeZone: shanghai).complete(state: state)

    XCTAssertTrue(output.contains("甲  \n乙  \n丙  \n丁"))
    XCTAssertFalse(output.contains("\r"))
  }

  func testMarkdownDocumentWritesUTF8AndExportFeedbackClassifiesResults()
    throws
  {
    let document = MarkdownDocument(text: "# Keep3\n你好\n")
    let wrapper = document.fileWrapperForWriting()
    XCTAssertEqual(
      wrapper.regularFileContents,
      Data("# Keep3\n你好\n".utf8)
    )

    XCTAssertNil(
      MarkdownExportFeedback.message(
        for: .success(URL(fileURLWithPath: "/tmp/Keep3.md"))
      )
    )
    XCTAssertNil(
      MarkdownExportFeedback.message(
        for: .failure(CocoaError(.userCancelled))
      )
    )
    XCTAssertEqual(
      MarkdownExportFeedback.message(
        for: .failure(CocoaError(.fileWriteNoPermission))
      ),
      "Markdown 文件未能保存。"
    )
  }
}
