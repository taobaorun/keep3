import AppKit
import SwiftUI

struct SidebarRowPressButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(
        !isEnabled
          ? 0.5 : configuration.isPressed ? 0.78 : 1
      )
      .animation(
        InteractionMotion.strongEaseOut(
          duration: InteractionMotion.pressInDuration
        ),
        value: configuration.isPressed
      )
  }
}

struct EditorView: View {
  @ObservedObject var model: AppModel
  @State private var newItemTitle = ""
  @State private var hoveredItemID: UUID?
  @FocusState private var focusedItemID: UUID?
  @FocusState private var isNewItemTitleFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        HStack(spacing: 12) {
          Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(width: 48, height: 48)
            .accessibilityLabel("Keep3")
            .accessibilityIdentifier("editor.brandLogo")

          Text("Keep3")
            .font(.title)
            .fontWeight(.semibold)
            .accessibilityIdentifier("editor.brandName")
        }
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

      if let pendingUndo = model.pendingArchiveUndo {
        HStack(spacing: 8) {
          Label(
            "已归档“\(pendingUndo.itemTitle)”",
            systemImage: "archivebox"
          )
          .font(.caption)
          .lineLimit(2)

          Spacer(minLength: 4)

          Button("撤销") {
            model.undoArchive(operationID: pendingUndo.operationID)
          }
          .buttonStyle(.borderless)
          .accessibilityIdentifier("editor.undoArchive")

          Button {
            model.dismissArchiveUndo(operationID: pendingUndo.operationID)
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("关闭撤销提示")
          .accessibilityIdentifier("editor.dismissArchiveUndo")
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .id(pendingUndo.operationID)
        .allowsHitTesting(
          model.pendingArchiveUndo?.operationID == pendingUndo.operationID
        )
        .transition(archiveUndoTransition)
      }

      Spacer(minLength: 16)

      if model.state.items.count < Keep3State.maximumItemCount {
        HStack(spacing: 8) {
          TextField(
            "",
            text: $newItemTitle,
            prompt: Text("添加一件事")
              .font(.system(size: NSFont.systemFontSize, weight: .regular))
          )
          .font(.system(size: NSFont.systemFontSize, weight: .regular))
          .textFieldStyle(.plain)
          .padding(.horizontal, 7)
          .frame(height: 22)
          .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 4)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 4)
              .stroke(
                isNewItemTitleFocused
                  ? Color("AccentColor") : Color(nsColor: .separatorColor),
                lineWidth: 1
              )
          }
          .focusEffectDisabled()
          .focused($isNewItemTitleFocused)
          .onSubmit(addItem)
          .accessibilityLabel("新事项标题")
          .accessibilityIdentifier("editor.newItemTitle")

          Button(action: addItem) {
            Image(systemName: "plus")
          }
          .buttonStyle(.bordered)
          .tint(.primary)
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
          .id(message)
          .transition(transientMessageTransition)
      }

      if let message = model.persistenceMessage {
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
          .accessibilityLabel("本地存储提示：\(message)")
          .id(message)
          .transition(transientMessageTransition)
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
        onArchive: {
          model.archiveItem(id: item.id)
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
        rowBackground(for: item)
      )
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(alignment: .leading) {
        if model.selectedItemID == item.id {
          Capsule()
            .fill(Color("AccentColor"))
            .frame(width: 3)
            .padding(.vertical, 6)
        }
      }
      .overlay {
        if focusedItemID == item.id {
          RoundedRectangle(cornerRadius: 6)
            .stroke(.primary.opacity(0.46), lineWidth: 1)
        }
      }
    }
    .buttonStyle(SidebarRowPressButtonStyle())
    .focused($focusedItemID, equals: item.id)
    .onHover { isHovered in
      hoveredItemID = isHovered ? item.id : nil
    }
    .accessibilityAddTraits(
      model.selectedItemID == item.id ? .isSelected : []
    )
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

  private func rowBackground(for item: FocusItem) -> Color {
    if model.selectedItemID == item.id {
      return Color("AccentColor").opacity(0.14)
    }
    if hoveredItemID == item.id {
      return Color.primary.opacity(0.055)
    }
    return .clear
  }

  private var archiveUndoTransition: AnyTransition {
    let insertion = AnyTransition.opacity
      .combined(
        with: .offset(y: reduceMotion ? 0 : -6)
      )
      .animation(
        InteractionMotion.strongEaseOut(
          duration:
            reduceMotion
            ? InteractionMotion.reducedMotionDuration
            : InteractionMotion.transientEntranceDuration
        )
      )
    let removal = AnyTransition.opacity.animation(
      InteractionMotion.strongEaseOut(
        duration: InteractionMotion.transientExitDuration
      )
    )
    return .asymmetric(insertion: insertion, removal: removal)
  }

  private var transientMessageTransition: AnyTransition {
    .asymmetric(
      insertion: .opacity.animation(
        InteractionMotion.strongEaseOut(
          duration:
            reduceMotion
            ? InteractionMotion.reducedMotionDuration
            : InteractionMotion.stateChangeDuration
        )
      ),
      removal: .opacity.animation(
        InteractionMotion.strongEaseOut(
          duration: InteractionMotion.transientExitDuration
        )
      )
    )
  }
}
