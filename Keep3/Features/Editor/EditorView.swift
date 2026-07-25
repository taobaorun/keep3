import SwiftUI

struct EditorView: View {
  @ObservedObject var model: AppModel
  @State private var newItemTitle = ""

  var body: some View {
    HSplitView {
      sidebar
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

      detail
        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 720, minHeight: 520)
    .accessibilityIdentifier("editor.root")
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Keep3")
          .font(.title)
          .fontWeight(.semibold)
        Text("把重要的事留在视线里")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Divider()

      Text("最重要的三件事")
        .font(.headline)

      if model.state.items.isEmpty {
        Text("先添加此刻最重要的一件事。")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        VStack(spacing: 6) {
          ForEach(Array(model.state.items.enumerated()), id: \.element.id) {
            index,
            item in
            itemButton(item, position: index + 1)
          }
        }
      }

      Spacer(minLength: 16)

      if model.state.items.count < Keep3State.maximumItemCount {
        HStack(spacing: 8) {
          TextField("添加一件事", text: $newItemTitle)
            .onSubmit(addItem)
            .accessibilityLabel("新事项标题")
            .accessibilityIdentifier("editor.newItemTitle")

          Button(action: addItem) {
            Image(systemName: "plus")
          }
          .buttonStyle(.borderedProminent)
          .disabled(
            newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
          .accessibilityLabel("添加事项")
          .accessibilityIdentifier("editor.addItem")
        }
      } else {
        Label("三件事已全部写下", systemImage: "checkmark")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let message = model.editorMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .accessibilityLabel("编辑错误：\(message)")
      }

      if let message = model.persistenceMessage {
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
          .accessibilityLabel("本地存储提示：\(message)")
      }
    }
    .padding(20)
  }

  @ViewBuilder
  private var detail: some View {
    if let item = model.selectedItem,
      let index = model.state.items.firstIndex(where: { $0.id == item.id })
    {
      ItemEditorView(
        item: item,
        position: index + 1,
        itemCount: model.state.items.count,
        isCurrentFocus: model.state.currentFocusID == item.id,
        onUpdate: { title, details, subitems in
          model.updateItem(
            id: item.id,
            title: title,
            details: details,
            subitems: subitems
          )
        },
        onMakeCurrent: {
          model.setCurrentFocus(id: item.id)
        },
        onMove: { destination in
          model.moveItem(id: item.id, to: destination)
        },
        onDelete: {
          model.removeItem(id: item.id)
        }
      )
      .id(item.id)
    } else {
      ContentUnavailableView {
        Label("还没有重点", systemImage: "scope")
      } description: {
        Text("在左侧写下第一件最重要的事。")
      }
    }
  }

  private func itemButton(
    _ item: FocusItem,
    position: Int
  ) -> some View {
    Button {
      model.selectItem(id: item.id)
    } label: {
      HStack(spacing: 8) {
        Text("\(position)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 16)

        Text(item.title)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)

        if model.state.currentFocusID == item.id {
          Label("当前", systemImage: "scope")
            .labelStyle(.titleAndIcon)
            .font(.caption)
        }
      }
      .padding(8)
      .contentShape(Rectangle())
      .background(
        model.selectedItemID == item.id
          ? Color.accentColor.opacity(0.14)
          : Color.clear
      )
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("editor.item.\(position)")
    .accessibilityLabel(
      model.state.currentFocusID == item.id
        ? "第 \(position) 件，\(item.title)，当前重点"
        : "第 \(position) 件，\(item.title)"
    )
  }

  private func addItem() {
    guard let id = model.addItem(title: newItemTitle) else {
      return
    }
    newItemTitle = ""
    model.selectItem(id: id)
  }
}
