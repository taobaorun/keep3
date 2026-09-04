import SwiftUI

struct ItemEditorView: View {
  let item: FocusItem
  let position: Int
  let itemCount: Int
  let isCurrentFocus: Bool
  let onUpdate: (String, String, [String]) -> Void
  let onMakeCurrent: () -> Void
  let onMove: (Int) -> Void
  let onArchive: () -> Void
  let onDelete: () -> Void

  @State private var title: String
  @State private var details: String
  @State private var subitems: [String]
  @State private var confirmsDeletion = false

  init(
    item: FocusItem,
    position: Int,
    itemCount: Int,
    isCurrentFocus: Bool,
    onUpdate: @escaping (String, String, [String]) -> Void,
    onMakeCurrent: @escaping () -> Void,
    onMove: @escaping (Int) -> Void,
    onArchive: @escaping () -> Void,
    onDelete: @escaping () -> Void
  ) {
    self.item = item
    self.position = position
    self.itemCount = itemCount
    self.isCurrentFocus = isCurrentFocus
    self.onUpdate = onUpdate
    self.onMakeCurrent = onMakeCurrent
    self.onMove = onMove
    self.onArchive = onArchive
    self.onDelete = onDelete
    _title = State(initialValue: item.title)
    _details = State(initialValue: item.details)
    _subitems = State(initialValue: item.subitems)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("第 \(position) 件")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(isCurrentFocus ? "当前重点" : "重点事项")
              .font(.title2)
              .fontWeight(.semibold)
          }

          Spacer()

          if isCurrentFocus {
            Label("当前重点", systemImage: "scope")
              .font(.callout)
          } else {
            Button("设为当前重点", systemImage: "scope", action: onMakeCurrent)
              .accessibilityIdentifier("editor.makeCurrent")
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("标题")
            .font(.headline)
          TextField("这件事是什么？", text: titleBinding)
            .accessibilityLabel("事项标题")
            .accessibilityIdentifier("editor.title")
          Text("\(title.count) / \(FocusItem.maximumTitleLength)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 8) {
          Text("说明")
            .font(.headline)
          TextEditor(text: detailsBinding)
            .font(.body)
            .frame(minHeight: 100)
            .padding(4)
            .background(.background)
            .overlay {
              RoundedRectangle(cornerRadius: 6)
                .stroke(.separator)
            }
            .accessibilityLabel("事项说明")
            .accessibilityIdentifier("editor.details")
          Text("\(details.count) / \(FocusItem.maximumDetailsLength)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("补充说明")
              .font(.headline)
            Spacer()
            Text("\(subitems.count) / \(FocusItem.maximumSubitemCount)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }

          ForEach(subitems.indices, id: \.self) { index in
            HStack(spacing: 8) {
              TextField(
                "补充说明 \(index + 1)",
                text: subitemBinding(at: index)
              )
              .accessibilityLabel("补充说明 \(index + 1)")
              .accessibilityIdentifier("editor.subitem.\(index + 1)")

              Button {
                removeSubitem(at: index)
              } label: {
                Image(systemName: "minus.circle")
              }
              .buttonStyle(.borderless)
              .accessibilityLabel("移除补充说明 \(index + 1)")
              .accessibilityIdentifier(
                "editor.removeSubitem.\(index + 1)"
              )
            }
          }

          Button("添加补充说明", systemImage: "plus", action: addSubitem)
            .disabled(subitems.count >= FocusItem.maximumSubitemCount)
            .accessibilityIdentifier("editor.addSubitem")
        }

        Divider()

        HStack {
          Button("上移", systemImage: "arrow.up") {
            onMove(position - 2)
          }
          .disabled(position == 1)
          .accessibilityIdentifier("editor.moveUp")

          Button("下移", systemImage: "arrow.down") {
            onMove(position)
          }
          .disabled(position == itemCount)
          .accessibilityIdentifier("editor.moveDown")

          Spacer()

          Button("归档", systemImage: "archivebox", action: onArchive)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("editor.archive")

          Menu {
            Button("永久删除…", systemImage: "trash", role: .destructive) {
              confirmsDeletion = true
            }
            .accessibilityIdentifier("editor.permanentDelete")
          } label: {
            Label("更多", systemImage: "ellipsis.circle")
          }
          .accessibilityIdentifier("editor.moreActions")
        }
      }
      .padding(28)
    }
    .confirmationDialog(
      "永久删除“\(item.title)”？",
      isPresented: $confirmsDeletion
    ) {
      Button("永久删除", role: .destructive, action: onDelete)
        .accessibilityIdentifier("editor.confirmDelete")
      Button("取消", role: .cancel) {}
        .accessibilityIdentifier("editor.cancelDelete")
    } message: {
      Text("这件事不会保存在历史记录中，且无法恢复。")
    }
  }

  private var titleBinding: Binding<String> {
    Binding(
      get: { title },
      set: { value in
        title = value
        onUpdate(value, details, subitems)
      }
    )
  }

  private var detailsBinding: Binding<String> {
    Binding(
      get: { details },
      set: { value in
        details = value
        onUpdate(title, value, subitems)
      }
    )
  }

  private func subitemBinding(at index: Int) -> Binding<String> {
    Binding(
      get: { subitems[index] },
      set: { value in
        var updatedSubitems = subitems
        updatedSubitems[index] = value
        subitems = updatedSubitems
        onUpdate(title, details, updatedSubitems)
      }
    )
  }

  private func addSubitem() {
    guard subitems.count < FocusItem.maximumSubitemCount else {
      return
    }
    subitems.append("")
    onUpdate(title, details, subitems)
  }

  private func removeSubitem(at index: Int) {
    subitems.remove(at: index)
    onUpdate(title, details, subitems)
  }
}
