import Foundation

struct FocusItem: Identifiable, Codable, Equatable, Sendable {
  enum ValidationError: Error, Equatable {
    case emptyTitle
    case titleTooLong
    case detailsTooLong
    case tooManySubitems
    case subitemTooLong(index: Int)
  }

  static let maximumTitleLength = 60
  static let maximumDetailsLength = 500
  static let maximumSubitemCount = 8
  static let maximumSubitemLength = 120

  let id: UUID
  private(set) var title: String
  private(set) var details: String
  private(set) var subitems: [String]

  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case details
    case subitems
  }

  init(
    id: UUID = UUID(),
    title: String,
    details: String = "",
    subitems: [String] = []
  ) throws {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    try Self.validate(
      title: normalizedTitle,
      details: details,
      subitems: subitems
    )

    self.id = id
    self.title = normalizedTitle
    self.details = details
    self.subitems = subitems
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let title = try container.decode(String.self, forKey: .title)
    let details = try container.decode(String.self, forKey: .details)
    let subitems = try container.decode([String].self, forKey: .subitems)

    do {
      try self.init(
        id: id,
        title: title,
        details: details,
        subitems: subitems
      )
    } catch {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Stored focus item violates Keep3 limits.",
          underlyingError: error
        )
      )
    }
  }

  private static func validate(
    title: String,
    details: String,
    subitems: [String]
  ) throws {
    guard !title.isEmpty else {
      throw ValidationError.emptyTitle
    }
    guard title.count <= maximumTitleLength else {
      throw ValidationError.titleTooLong
    }
    guard details.count <= maximumDetailsLength else {
      throw ValidationError.detailsTooLong
    }
    guard subitems.count <= maximumSubitemCount else {
      throw ValidationError.tooManySubitems
    }

    for (index, subitem) in subitems.enumerated()
    where subitem.count > maximumSubitemLength {
      throw ValidationError.subitemTooLong(index: index)
    }
  }
}
