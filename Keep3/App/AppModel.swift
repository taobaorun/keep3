import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var state: Keep3State
  @Published private(set) var selectedItemID: UUID?
  @Published private(set) var editorMessage: String?
  @Published private(set) var persistenceMessage: String?

  var onStateChange: ((Keep3State) -> Void)?
  private let stateStore: (any StateStore)?

  init(state: Keep3State = Keep3State()) {
    self.state = state
    selectedItemID = state.currentFocusID
    stateStore = nil
  }

  init(stateStore: any StateStore) {
    self.stateStore = stateStore

    do {
      let result = try stateStore.load()
      state = result.state
      selectedItemID = result.state.currentFocusID
      persistenceMessage = result.message
    } catch {
      state = Keep3State()
      selectedItemID = nil
      persistenceMessage = "无法打开本地数据；原文件未被修改。"
    }
  }

  static func live() -> AppModel {
    do {
      return AppModel(
        stateStore: try JSONStateStore.applicationSupport()
      )
    } catch {
      let model = AppModel()
      model.persistenceMessage = "无法访问 Application Support，当前更改不会被保存。"
      return model
    }
  }

  var selectedItem: FocusItem? {
    guard let selectedItemID else {
      return nil
    }
    return state.items.first { $0.id == selectedItemID }
  }

  @discardableResult
  func addItem(
    title: String,
    details: String = "",
    subitems: [String] = []
  ) -> UUID? {
    do {
      let item = try FocusItem(
        title: title,
        details: details,
        subitems: subitems
      )
      var updatedState = state
      try updatedState.add(item)

      selectedItemID = item.id
      editorMessage = nil
      publish(updatedState)
      return item.id
    } catch {
      editorMessage = message(for: error)
      return nil
    }
  }

  func updateItem(
    id: UUID,
    title: String,
    details: String,
    subitems: [String]
  ) {
    do {
      var updatedState = state
      try updatedState.updateItem(
        id: id,
        title: title,
        details: details,
        subitems: subitems
      )

      editorMessage = nil
      publish(updatedState)
    } catch {
      editorMessage = message(for: error)
    }
  }

  func removeItem(id: UUID) {
    do {
      var updatedState = state
      try updatedState.remove(id: id)

      if selectedItemID == id {
        selectedItemID = updatedState.currentFocusID
      }
      editorMessage = nil
      publish(updatedState)
    } catch {
      editorMessage = message(for: error)
    }
  }

  func setCurrentFocus(id: UUID) {
    do {
      var updatedState = state
      try updatedState.setCurrentFocus(id: id)

      selectedItemID = id
      editorMessage = nil
      publish(updatedState)
    } catch {
      editorMessage = message(for: error)
    }
  }

  func moveItem(id: UUID, to destinationIndex: Int) {
    do {
      var updatedState = state
      try updatedState.moveItem(id: id, to: destinationIndex)

      editorMessage = nil
      publish(updatedState)
    } catch {
      editorMessage = message(for: error)
    }
  }

  func selectItem(id: UUID) {
    guard state.items.contains(where: { $0.id == id }) else {
      editorMessage = "找不到这件事。"
      return
    }
    selectedItemID = id
    editorMessage = nil
  }

  private func publish(_ updatedState: Keep3State) {
    guard updatedState != state else {
      return
    }
    state = updatedState
    onStateChange?(updatedState)

    guard let stateStore else {
      return
    }
    do {
      try stateStore.save(updatedState)
      persistenceMessage = nil
    } catch {
      persistenceMessage = "本地保存失败；当前内容仍保留在本次运行中。"
    }
  }

  private func message(for error: Error) -> String {
    switch error {
    case FocusItem.ValidationError.emptyTitle:
      return "标题不能为空。"
    case FocusItem.ValidationError.titleTooLong:
      return "标题最多 60 个字符。"
    case FocusItem.ValidationError.detailsTooLong:
      return "说明最多 500 个字符。"
    case FocusItem.ValidationError.tooManySubitems:
      return "每件事最多包含 8 条补充说明。"
    case FocusItem.ValidationError.subitemTooLong:
      return "每条补充说明最多 120 个字符。"
    case Keep3State.MutationError.itemLimitReached:
      return "最多只能保留三件事。"
    case Keep3State.MutationError.invalidDestinationIndex:
      return "无法移动到这个位置。"
    case Keep3State.MutationError.duplicateItemID,
      Keep3State.MutationError.itemNotFound:
      return "找不到这件事。"
    default:
      return "无法更新内容。"
    }
  }
}
