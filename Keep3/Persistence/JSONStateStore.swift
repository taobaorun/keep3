import Foundation

final class JSONStateStore: StateStore {
  enum StoreError: Error {
    case unsupportedSchemaVersion(Int)
    case recoveryFailed(readError: Error, preservationError: Error)
  }

  private struct SchemaHeader: Decodable {
    let schemaVersion: Int
  }

  private struct StoredStateV1: Decodable {
    let schemaVersion: Int
    let items: [FocusItem]
    let currentFocusID: UUID?
  }

  private struct StoredStateV2: Codable {
    let schemaVersion: Int
    let items: [FocusItem]
    let currentFocusID: UUID?
    let archivedItems: [ArchivedFocusItem]
  }

  static let currentSchemaVersion = 2

  let fileURL: URL

  private let fileManager: FileManager
  private let recoveryFileName: () -> String

  init(
    fileURL: URL,
    fileManager: FileManager = .default,
    recoveryFileName: @escaping () -> String = JSONStateStore.defaultRecoveryFileName
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    self.recoveryFileName = recoveryFileName
  }

  static func applicationSupport(
    fileManager: FileManager = .default
  ) throws -> JSONStateStore {
    let applicationSupportURL = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let keep3DirectoryURL =
      applicationSupportURL
      .appendingPathComponent("Keep3", isDirectory: true)
    try fileManager.createDirectory(
      at: keep3DirectoryURL,
      withIntermediateDirectories: true
    )
    return JSONStateStore(
      fileURL: keep3DirectoryURL.appendingPathComponent("state.json"),
      fileManager: fileManager
    )
  }

  func load() throws -> StateLoadResult {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return StateLoadResult(state: Keep3State())
    }

    do {
      let data = try Data(contentsOf: fileURL)
      let decoder = JSONDecoder()
      let header = try decoder.decode(SchemaHeader.self, from: data)
      let state: Keep3State
      switch header.schemaVersion {
      case 1:
        let storedState = try decoder.decode(StoredStateV1.self, from: data)
        state = try Keep3State(
          items: storedState.items,
          currentFocusID: storedState.currentFocusID
        )
      case Self.currentSchemaVersion:
        let storedState = try decoder.decode(StoredStateV2.self, from: data)
        state = try Keep3State(
          items: storedState.items,
          currentFocusID: storedState.currentFocusID,
          archivedItems: storedState.archivedItems
        )
      default:
        throw StoreError.unsupportedSchemaVersion(header.schemaVersion)
      }
      return StateLoadResult(state: state)
    } catch {
      return try preserveUnreadableState(readError: error)
    }
  }

  func save(_ state: Keep3State) throws {
    _ = try Keep3State(
      items: state.items,
      currentFocusID: state.currentFocusID,
      archivedItems: state.archivedItems
    )
    let storedState = StoredStateV2(
      schemaVersion: Self.currentSchemaVersion,
      items: state.items,
      currentFocusID: state.currentFocusID,
      archivedItems: state.archivedItems
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(storedState)

    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
  }

  private func preserveUnreadableState(
    readError: Error
  ) throws -> StateLoadResult {
    let recoveryURL = fileURL.deletingLastPathComponent()
      .appendingPathComponent(recoveryFileName())

    do {
      try fileManager.moveItem(at: fileURL, to: recoveryURL)
    } catch {
      throw StoreError.recoveryFailed(
        readError: readError,
        preservationError: error
      )
    }

    return StateLoadResult(
      state: Keep3State(),
      recoveryFileURL: recoveryURL,
      message: "原有数据无法读取，已保留为 \(recoveryURL.lastPathComponent)。"
    )
  }

  private static func defaultRecoveryFileName() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "state.corrupt-\(formatter.string(from: Date())).json"
  }
}
