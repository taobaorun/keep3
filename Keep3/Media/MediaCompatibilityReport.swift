import Foundation

enum MediaAdapterStatus: String, Codable, Equatable, Sendable {
  case available
  case unavailable
}

struct MediaCompatibilityReport: Equatable, Sendable {
  static let protocolVersion = 2

  let status: MediaAdapterStatus
  let missingMandatorySymbols: [String]
  let missingOptionalSymbols: [String]
  let optionalCapabilities: Set<MediaCapability>

  static let unavailable = MediaCompatibilityReport(
    status: .unavailable,
    missingMandatorySymbols: [],
    missingOptionalSymbols: [],
    optionalCapabilities: []
  )

  init(
    status: MediaAdapterStatus,
    missingMandatorySymbols: [String],
    missingOptionalSymbols: [String],
    optionalCapabilities: Set<MediaCapability>
  ) {
    self.status = status
    self.missingMandatorySymbols = missingMandatorySymbols
    self.missingOptionalSymbols = missingOptionalSymbols
    self.optionalCapabilities = optionalCapabilities
  }

  init?(propertyList: NSDictionary) {
    guard
      let protocolVersion = propertyList["protocolVersion"] as? NSNumber,
      protocolVersion.exactUInt64 == UInt64(Self.protocolVersion),
      let statusValue = propertyList["status"] as? String,
      let status = MediaAdapterStatus(rawValue: statusValue),
      let missingMandatorySymbols = propertyList["missingMandatorySymbols"] as? [String],
      let missingOptionalSymbols = propertyList["missingOptionalSymbols"] as? [String],
      let capabilityValues = propertyList["optionalCapabilities"] as? [String]
    else {
      return nil
    }

    self.init(
      status: status,
      missingMandatorySymbols: missingMandatorySymbols,
      missingOptionalSymbols: missingOptionalSymbols,
      optionalCapabilities: Set(capabilityValues.compactMap(MediaCapability.init(rawValue:)))
    )
  }

  var propertyList: NSDictionary {
    [
      "protocolVersion": NSNumber(value: Self.protocolVersion),
      "status": status.rawValue,
      "missingMandatorySymbols": missingMandatorySymbols,
      "missingOptionalSymbols": missingOptionalSymbols,
      "optionalCapabilities": optionalCapabilities.map(\.rawValue).sorted(),
    ]
  }
}
