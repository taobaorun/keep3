import AppKit
import ApplicationServices
import Foundation

enum ProviderEnrichmentCapability: String, Hashable, Sendable {
  case favorite
  case shuffle
  case repeatMode
}

enum ProviderAutomationCommand: String, Equatable, Sendable {
  case musicFavorite
  case musicToggleShuffle
  case musicCycleRepeat
  case spotifyFavorite
  case netEaseFavorite
}

enum ProviderCommandBackend: Equatable, Sendable {
  case automation(
    targetBundleIdentifier: String,
    command: ProviderAutomationCommand
  )
}

struct ProviderEnrichment: Equatable, Sendable {
  let bundleIdentifier: String
  let capabilityBackends:
    [ProviderEnrichmentCapability: ProviderCommandBackend]
}

struct ProviderAutomationTarget: Equatable, Sendable {
  let bundleIdentifier: String
  let eventClass: UInt32
  let eventID: UInt32
}

enum AutomationPermissionOutcome: Equatable, Sendable {
  case granted
  case denied
  case revoked
  case timedOut
  case providerNotRunning
  case missingScriptingSupport
}

protocol AutomationPermissionRequesting: Sendable {
  func requestPermission(
    for target: ProviderAutomationTarget
  ) async -> AutomationPermissionOutcome
}

struct ProviderEnrichmentService: Sendable {
  static let supportedBundleIdentifiers: Set<String> = Set(registry.keys)

  private struct ProviderDefinition: Sendable {
    let target: ProviderAutomationTarget
    let commands:
      [ProviderEnrichmentCapability: ProviderAutomationCommand]
  }

  private static let registry: [String: ProviderDefinition] = [
    "com.apple.Music": ProviderDefinition(
      target: ProviderAutomationTarget(
        bundleIdentifier: "com.apple.Music",
        eventClass: UInt32(kCoreEventClass),
        eventID: UInt32(kAEGetData)
      ),
      commands: [
        .favorite: .musicFavorite,
        .shuffle: .musicToggleShuffle,
        .repeatMode: .musicCycleRepeat,
      ]
    ),
    "com.spotify.client": ProviderDefinition(
      target: ProviderAutomationTarget(
        bundleIdentifier: "com.spotify.client",
        eventClass: UInt32(kCoreEventClass),
        eventID: UInt32(kAEGetData)
      ),
      commands: [.favorite: .spotifyFavorite]
    ),
    "com.netease.163music": ProviderDefinition(
      target: ProviderAutomationTarget(
        bundleIdentifier: "com.netease.163music",
        eventClass: UInt32(kCoreEventClass),
        eventID: UInt32(kAEGetData)
      ),
      commands: [.favorite: .netEaseFavorite]
    ),
  ]

  private let permissionRequester: any AutomationPermissionRequesting
  private let isApplicationRunning: @Sendable (String) -> Bool

  init(
    permissionRequester: any AutomationPermissionRequesting,
    isApplicationRunning: @escaping @Sendable (String) -> Bool
  ) {
    self.permissionRequester = permissionRequester
    self.isApplicationRunning = isApplicationRunning
  }

  static func live() -> ProviderEnrichmentService {
    ProviderEnrichmentService(
      permissionRequester: SystemAutomationPermissionRequester(),
      isApplicationRunning: { bundleIdentifier in
        !NSRunningApplication.runningApplications(
          withBundleIdentifier: bundleIdentifier
        ).isEmpty
      }
    )
  }

  static func accepts(bundleIdentifier: String) -> Bool {
    registry[bundleIdentifier] != nil
  }

  // This is deliberately the sole prompting entry point. Launch, playback,
  // and baseline MediaRemote delivery never call it.
  func requestUserInitiatedEnrichment(
    for session: MediaSession
  ) async -> ProviderEnrichment? {
    guard let bundleIdentifier = session.sourceBundleIdentifier,
      let provider = Self.registry[bundleIdentifier],
      provider.target.bundleIdentifier == bundleIdentifier,
      isApplicationRunning(bundleIdentifier)
    else {
      return nil
    }

    guard
      await permissionRequester.requestPermission(for: provider.target)
        == .granted
    else {
      return nil
    }

    return ProviderEnrichment(
      bundleIdentifier: bundleIdentifier,
      capabilityBackends: provider.commands.reduce(into: [:]) {
        backends,
        entry in
        backends[entry.key] = .automation(
          targetBundleIdentifier: provider.target.bundleIdentifier,
          command: entry.value
        )
      }
    )
  }
}

private struct SystemAutomationPermissionRequester:
  AutomationPermissionRequesting
{
  func requestPermission(
    for target: ProviderAutomationTarget
  ) -> AutomationPermissionOutcome {
    guard let identifierData = target.bundleIdentifier.data(using: .utf8)
    else {
      return .missingScriptingSupport
    }

    var address = AEAddressDesc()
    let createStatus = identifierData.withUnsafeBytes { bytes in
      AECreateDesc(
        DescType(typeApplicationBundleID),
        bytes.baseAddress,
        identifierData.count,
        &address
      )
    }
    guard createStatus == noErr else {
      return .missingScriptingSupport
    }
    defer { AEDisposeDesc(&address) }

    let status = AEDeterminePermissionToAutomateTarget(
      &address,
      AEEventClass(target.eventClass),
      AEEventID(target.eventID),
      true
    )
    switch status {
    case noErr:
      return .granted
    case OSStatus(errAEEventNotPermitted):
      return .denied
    case OSStatus(procNotFound):
      return .providerNotRunning
    default:
      return .missingScriptingSupport
    }
  }
}
