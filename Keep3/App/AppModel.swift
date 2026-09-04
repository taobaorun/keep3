import Combine
import Foundation

struct PendingArchiveUndo: Equatable, Sendable {
  let operationID: UUID
  let archiveID: UUID
  let itemTitle: String
  let originalIndex: Int
  let restoresCurrentFocus: Bool
}

@MainActor
final class AppModel: ObservableObject {
  private static let archiveUndoDuration: TimeInterval = 8

  @Published private(set) var state: Keep3State
  @Published private(set) var selectedItemID: UUID?
  @Published private(set) var editorMessage: String?
  @Published private(set) var persistenceMessage: String?
  @Published private(set) var pendingArchiveUndo: PendingArchiveUndo?

  var onStateChange: ((Keep3State) -> Void)?
  private let stateStore: (any StateStore)?
  private let now: () -> Date
  private let archiveUndoScheduler: any AppTimerScheduling
  private var archiveUndoTimer: (any AppTimerCancellation)?

  init(
    state: Keep3State = Keep3State(),
    now: @escaping () -> Date = Date.init,
    archiveUndoScheduler: any AppTimerScheduling = TaskAppTimerScheduler()
  ) {
    self.state = state
    self.now = now
    self.archiveUndoScheduler = archiveUndoScheduler
    selectedItemID = state.currentFocusID
    stateStore = nil
  }

  init(
    stateStore: any StateStore,
    now: @escaping () -> Date = Date.init,
    archiveUndoScheduler: any AppTimerScheduling = TaskAppTimerScheduler()
  ) {
    self.stateStore = stateStore
    self.now = now
    self.archiveUndoScheduler = archiveUndoScheduler

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

  func archiveItem(id: UUID) {
    do {
      guard let originalIndex = state.items.firstIndex(where: { $0.id == id })
      else {
        throw Keep3State.MutationError.itemNotFound
      }
      let restoresCurrentFocus = state.currentFocusID == id
      var updatedState = state
      let archivedItem = try updatedState.archive(id: id, at: now())

      selectedItemID = updatedState.currentFocusID
      editorMessage = nil
      publish(updatedState, invalidatingArchiveUndo: false)
      beginArchiveUndo(
        PendingArchiveUndo(
          operationID: UUID(),
          archiveID: archivedItem.id,
          itemTitle: archivedItem.item.title,
          originalIndex: originalIndex,
          restoresCurrentFocus: restoresCurrentFocus
        ))
    } catch {
      editorMessage = message(for: error)
    }
  }

  func undoArchive(operationID: UUID) {
    guard let pendingArchiveUndo else {
      editorMessage = "这次归档已无法撤销。"
      return
    }
    guard pendingArchiveUndo.operationID == operationID else {
      return
    }

    do {
      var updatedState = state
      try updatedState.undoArchive(
        id: pendingArchiveUndo.archiveID,
        to: pendingArchiveUndo.originalIndex,
        restoringCurrentFocus: pendingArchiveUndo.restoresCurrentFocus
      )

      selectedItemID = pendingArchiveUndo.archiveID
      clearArchiveUndo()
      editorMessage = nil
      publish(updatedState, invalidatingArchiveUndo: false)
    } catch {
      clearArchiveUndo()
      editorMessage = message(for: error)
    }
  }

  func dismissArchiveUndo(operationID: UUID) {
    guard pendingArchiveUndo?.operationID == operationID else {
      return
    }
    clearArchiveUndo()
  }

  func removeArchivedItem(id: UUID) {
    do {
      var updatedState = state
      try updatedState.removeArchived(id: id)

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

  private func publish(
    _ updatedState: Keep3State,
    invalidatingArchiveUndo: Bool = true
  ) {
    guard updatedState != state else {
      return
    }
    if invalidatingArchiveUndo {
      clearArchiveUndo()
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

  private func beginArchiveUndo(_ pendingUndo: PendingArchiveUndo) {
    clearArchiveUndo()
    pendingArchiveUndo = pendingUndo
    archiveUndoTimer = archiveUndoScheduler.schedule(
      after: Self.archiveUndoDuration
    ) { [weak self] in
      self?.dismissArchiveUndo(operationID: pendingUndo.operationID)
    }
  }

  private func clearArchiveUndo() {
    archiveUndoTimer?.cancel()
    archiveUndoTimer = nil
    pendingArchiveUndo = nil
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
