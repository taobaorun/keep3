import Foundation

struct StateLoadResult: Equatable {
  let state: Keep3State
  let recoveryFileURL: URL?
  let message: String?

  init(
    state: Keep3State,
    recoveryFileURL: URL? = nil,
    message: String? = nil
  ) {
    self.state = state
    self.recoveryFileURL = recoveryFileURL
    self.message = message
  }
}

protocol StateStore {
  func load() throws -> StateLoadResult
  func save(_ state: Keep3State) throws
}
