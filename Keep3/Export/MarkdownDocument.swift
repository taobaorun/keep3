import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
  static let contentType = UTType(filenameExtension: "md") ?? .plainText
  static var readableContentTypes: [UTType] { [contentType] }
  static var writableContentTypes: [UTType] { [contentType] }

  let text: String

  init(text: String) {
    self.text = text
  }

  init(configuration: ReadConfiguration) throws {
    guard
      let data = configuration.file.regularFileContents,
      let text = String(data: data, encoding: .utf8)
    else {
      throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    self.text = text
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    fileWrapperForWriting()
  }

  func fileWrapperForWriting() -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(text.utf8))
  }
}

enum MarkdownExportFeedback {
  static let failureMessage = "Markdown 文件未能保存。"

  static func message(for result: Result<URL, any Error>) -> String? {
    switch result {
    case .success:
      return nil
    case .failure(let error):
      let cocoaError = error as NSError
      if cocoaError.domain == NSCocoaErrorDomain,
        cocoaError.code == CocoaError.userCancelled.rawValue
      {
        return nil
      }
      return failureMessage
    }
  }
}
