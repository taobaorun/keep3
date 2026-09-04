import Foundation

struct MarkdownExporter {
  let timeZone: TimeZone

  init(timeZone: TimeZone = .current) {
    self.timeZone = timeZone
  }

  func complete(state: Keep3State) -> String {
    var lines = ["# Keep3 导出", "", "## 当前三件事", ""]

    if state.items.isEmpty {
      lines.append("_当前没有重要事项。_")
    } else {
      for (index, item) in state.items.enumerated() {
        let focusMarker = state.currentFocusID == item.id ? "（当前重点）" : ""
        lines.append("### \(index + 1)\(focusMarker)")
        lines.append("")
        lines.append(contentsOf: contentLines(for: item))
        lines.append("")
      }
    }

    lines.append("## 历史记录")
    lines.append("")
    if state.archivedItems.isEmpty {
      lines.append("_还没有归档记录。_")
    } else {
      for archivedItem in state.archivedItems {
        lines.append("### \(escaped(archivedItem.item.title))")
        lines.append("")
        lines.append("**归档时间：** \(timestamp(archivedItem.archivedAt))")
        lines.append("")
        lines.append(
          contentsOf: contentLines(
            for: archivedItem.item,
            includingTitle: false
          ))
        lines.append("")
      }
    }

    return normalizedDocument(lines)
  }

  func archivedItem(_ archivedItem: ArchivedFocusItem) -> String {
    var lines = [
      "# Keep3 历史记录",
      "",
      "**归档时间：** \(timestamp(archivedItem.archivedAt))",
      "",
    ]
    lines.append(contentsOf: contentLines(for: archivedItem.item))
    return normalizedDocument(lines)
  }

  private func contentLines(
    for item: FocusItem,
    includingTitle: Bool = true
  ) -> [String] {
    var lines: [String] = []
    if includingTitle {
      lines.append("**标题：** \(escaped(item.title))")
    }

    if !item.details.isEmpty {
      if !lines.isEmpty {
        lines.append("")
      }
      lines.append("**说明：**")
      lines.append("")
      lines.append(escaped(item.details))
    }

    if !item.subitems.isEmpty {
      if !lines.isEmpty {
        lines.append("")
      }
      lines.append("**补充说明：**")
      lines.append("")
      lines.append(contentsOf: item.subitems.map { "- \(escaped($0))" })
    }

    return lines
  }

  private func escaped(_ value: String) -> String {
    let normalizedValue =
      value
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var escapedValue = normalizedValue.replacingOccurrences(
      of: "\\",
      with: "\\\\"
    )
    for token in [
      "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-",
      ".", "/", ":", ";", "<", "=", ">", "?", "@", "[", "]", "^", "_",
      "`", "{", "|", "}", "~",
    ] {
      escapedValue = escapedValue.replacingOccurrences(
        of: token,
        with: "\\\(token)"
      )
    }
    return escapedValue.replacingOccurrences(of: "\n", with: "  \n")
  }

  private func timestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

    let seconds = timeZone.secondsFromGMT(for: date)
    let absoluteSeconds = abs(seconds)
    let sign = seconds >= 0 ? "+" : "-"
    let hours = absoluteSeconds / 3_600
    let minutes = (absoluteSeconds % 3_600) / 60
    let offset = String(format: "%@%02d:%02d", sign, hours, minutes)
    return "\(formatter.string(from: date)) \(offset)"
  }

  private func normalizedDocument(_ lines: [String]) -> String {
    var normalized = lines
    while normalized.last?.isEmpty == true {
      normalized.removeLast()
    }
    return normalized.joined(separator: "\n") + "\n"
  }
}
