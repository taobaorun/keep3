import Darwin
import Foundation

final class MediaRemoteService: NSObject, MediaRemoteServiceProtocol,
  @unchecked Sendable
{
  private static let frameworkPath =
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

  private let queue = DispatchQueue(
    label: "dev.keep3.mediaremote.service",
    qos: .userInitiated
  )
  private let clientStateLock = NSLock()
  private var clientGeneration: UInt64 = 0
  private var activeClientGeneration: UInt64?
  private var client: (any MediaRemoteClientProtocol)?
  private var runtime: MediaRemoteRuntime?
  private var observerTokens: [NSObjectProtocol] = []
  private var pendingRefresh: DispatchWorkItem?
  private var pendingDormantUpgrade: DispatchWorkItem?
  private var pendingAvailabilityRecovery: DispatchWorkItem?
  private var availabilityRecoveryPolicy =
    MediaRemoteAvailabilityRecoveryPolicy()
  private var monitoringGeneration: UInt64 = 0
  private var monitoringClientGeneration: UInt64?
  private var contentRevision: UInt64 = 0
  private var artworkRevision: UInt64 = 0
  private var currentSessionID: String?
  private var currentClient: AnyObject?
  private var currentSourceBundleIdentifier: String?
  private var currentContentIdentity: ContentIdentity?
  private var currentCapabilities: Set<MediaCapability> = []
  private var currentCapabilityRevision: UInt64 = 0
  private var currentArtworkData: Data?
  private var currentArtworkMIMEType: String?
  // Learned only from MediaRemote sessions that expose playback control.
  // Keeping this across monitoring restarts lets a known player recover dormant.
  private var discoveredPlayerBundleIdentifiers: Set<String> = []
  private var hostRunningApplications: [MediaRemoteRunningApplication] = []
  private var hostFrontmostBundleIdentifier: String?

  func attach(client: any MediaRemoteClientProtocol) {
    clientStateLock.withLock {
      clientGeneration &+= 1
      activeClientGeneration = clientGeneration
    }
    self.client = client
  }

  func invalidateClient() {
    clientStateLock.withLock {
      activeClientGeneration = nil
    }
    queue.async { [weak self] in
      guard let self else {
        return
      }
      self.stopMonitoringOnQueue()
      self.client = nil
    }
  }

  func compatibilityReport(
    reply: @escaping @Sendable (NSDictionary) -> Void
  ) {
    reply(Self.probe().propertyList)
  }

  func startMonitoring(
    runningApplications: NSArray,
    frontmostBundleIdentifier: String?,
    reply: @escaping @Sendable (Bool) -> Void
  ) {
    let runningApplications = Self.runningApplications(
      from: runningApplications
    )
    let frontmostBundleIdentifier = Self.bundleIdentifier(
      from: frontmostBundleIdentifier
    )
    guard let clientGeneration = currentClientGeneration() else {
      reply(false)
      return
    }
    queue.async { [weak self] in
      guard let self, self.acceptsClient(clientGeneration),
        self.client != nil
      else {
        reply(false)
        return
      }
      self.stopMonitoringOnQueue()
      self.hostRunningApplications = runningApplications
      self.hostFrontmostBundleIdentifier = frontmostBundleIdentifier
      guard
        let runtime = MediaRemoteRuntime(
          frameworkPath: Self.frameworkPath
        )
      else {
        reply(false)
        return
      }

      self.runtime = runtime
      self.monitoringClientGeneration = clientGeneration
      let generation = self.monitoringGeneration
      runtime.registerNotifications(on: self.queue)
      self.installObservers(generation: generation)
      self.refresh(generation: generation)
      reply(true)
    }
  }

  func updateWorkspaceContext(
    runningApplications: NSArray,
    frontmostBundleIdentifier: String?
  ) {
    let runningApplications = Self.runningApplications(
      from: runningApplications
    )
    let frontmostBundleIdentifier = Self.bundleIdentifier(
      from: frontmostBundleIdentifier
    )
    guard let clientGeneration = currentClientGeneration() else {
      return
    }
    queue.async { [weak self] in
      guard let self,
        self.acceptsClient(clientGeneration),
        self.monitoringClientGeneration == clientGeneration,
        self.runtime != nil
      else {
        return
      }
      self.hostRunningApplications = runningApplications
      self.hostFrontmostBundleIdentifier = frontmostBundleIdentifier
      self.scheduleRefresh(generation: self.monitoringGeneration)
    }
  }

  func stopMonitoring() {
    queue.async { [weak self] in
      self?.stopMonitoringOnQueue()
    }
  }

  func sendCommand(
    _ action: String,
    sessionID: String,
    capabilityRevision: NSNumber,
    value: NSNumber?,
    reply: @escaping @Sendable (Bool) -> Void
  ) {
    guard let clientGeneration = currentClientGeneration() else {
      reply(false)
      return
    }
    queue.async { [weak self] in
      guard let self, self.acceptsClient(clientGeneration),
        self.monitoringClientGeneration == clientGeneration,
        self.currentSessionID == sessionID,
        let command = MediaRemoteCommandName(rawValue: action),
        capabilityRevision.exactUInt64 == self.currentCapabilityRevision,
        self.currentCapabilities.contains(command.requiredCapability)
      else {
        reply(false)
        return
      }
      guard let runtime = self.runtime else {
        reply(false)
        return
      }
      let shouldUpgradeDormantPlayer =
        command == .togglePlayPause
        && self.currentContentIdentity?.hasMetadata == false
      runtime.send(
        command: command,
        value: value,
        to: self.currentClient,
        on: self.queue
      ) { [weak self] accepted in
        guard let self,
          self.acceptsClient(clientGeneration),
          self.monitoringClientGeneration == clientGeneration,
          self.currentSessionID == sessionID,
          capabilityRevision.exactUInt64 == self.currentCapabilityRevision
        else {
          reply(false)
          return
        }
        if accepted, shouldUpgradeDormantPlayer {
          self.scheduleDormantUpgrade(generation: self.monitoringGeneration)
        }
        reply(accepted)
      }
    }
  }

  private static func probe() -> MediaCompatibilityReport {
    guard let handle = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else {
      return .init(
        status: .unavailable,
        missingMandatorySymbols:
          MediaRemoteSymbolResolver.mandatorySymbols,
        missingOptionalSymbols: [],
        optionalCapabilities: []
      )
    }
    defer { dlclose(handle) }

    return MediaRemoteSymbolResolver.resolve { symbol in
      dlsym(handle, symbol)
    }
  }

  private static func runningApplications(
    from propertyLists: NSArray
  ) -> [MediaRemoteRunningApplication] {
    (propertyLists as? [NSDictionary] ?? [])
      .compactMap(MediaRemoteRunningApplication.init(propertyList:))
  }

  private static func bundleIdentifier(from value: String?) -> String? {
    MediaSession.bounded(
      value,
      maximum: MediaSession.maximumBundleIdentifierBytes
    )
  }

  private func installObservers(generation: UInt64) {
    let names = [
      "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
      "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
      "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    ]
    observerTokens = names.map { name in
      NotificationCenter.default.addObserver(
        forName: Notification.Name(name),
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.scheduleRefresh(generation: generation)
      }
    }
  }

  private func scheduleRefresh(generation: UInt64) {
    queue.async { [weak self] in
      guard let self, generation == self.monitoringGeneration else {
        return
      }
      self.pendingRefresh?.cancel()
      let work = DispatchWorkItem { [weak self] in
        self?.refresh(generation: generation)
      }
      self.pendingRefresh = work
      self.queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
  }

  private func scheduleDormantUpgrade(
    generation: UInt64,
    attempt: Int = 0
  ) {
    guard generation == monitoringGeneration,
      MediaRemoteDormantPlayerPolicy.upgradeRetryDelays.indices.contains(
        attempt
      )
    else {
      return
    }
    pendingDormantUpgrade?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, generation == self.monitoringGeneration else {
        return
      }
      self.refresh(generation: generation)
      self.scheduleDormantUpgrade(
        generation: generation,
        attempt: attempt + 1
      )
    }
    pendingDormantUpgrade = work
    queue.asyncAfter(
      deadline:
        .now()
        + MediaRemoteDormantPlayerPolicy.upgradeRetryDelays[attempt],
      execute: work
    )
  }

  private func scheduleAvailabilityRecovery(generation: UInt64) {
    guard generation == monitoringGeneration,
      pendingAvailabilityRecovery == nil
    else {
      return
    }
    let hasDiscoveredPlayerRunning =
      hostRunningApplications.contains {
        discoveredPlayerBundleIdentifiers.contains($0.bundleIdentifier)
      }
    guard
      let delay = availabilityRecoveryPolicy.nextRetryDelay(
        hasDiscoveredPlayerRunning: hasDiscoveredPlayerRunning
      )
    else {
      return
    }
    let work = DispatchWorkItem { [weak self] in
      guard let self, generation == self.monitoringGeneration else {
        return
      }
      self.pendingAvailabilityRecovery = nil
      self.refresh(generation: generation)
    }
    pendingAvailabilityRecovery = work
    queue.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func refresh(generation: UInt64) {
    guard generation == monitoringGeneration, let runtime else {
      publishUnavailable(generation: generation)
      return
    }

    runtime.getNowPlayingInfo(on: queue) { [weak self] information in
      guard let self,
        self.isCurrent(runtime: runtime, generation: generation)
      else {
        return
      }
      guard let information, information.count > 0 else {
        self.refreshInactiveClient(
          runtime: runtime,
          generation: generation
        )
        return
      }
      runtime.getIsPlaying(on: self.queue) { [weak self] isPlaying in
        guard let self,
          self.isCurrent(runtime: runtime, generation: generation)
        else {
          return
        }
        runtime.getApplicationPID(on: self.queue) { [weak self] pid in
          guard let self,
            self.isCurrent(runtime: runtime, generation: generation)
          else {
            return
          }
          let application = self.hostRunningApplications.first {
            $0.processIdentifier == pid
          }
          guard
            pid <= 0
              || application != nil
          else {
            self.refreshInactiveClient(
              runtime: runtime,
              generation: generation
            )
            return
          }
          runtime.getSupportedCapabilities(on: self.queue) {
            [weak self] capabilities in
            guard let self,
              self.isCurrent(runtime: runtime, generation: generation)
            else {
              return
            }
            guard capabilities.contains(.playPause) else {
              self.refreshInactiveClient(
                runtime: runtime,
                generation: generation
              )
              return
            }
            self.publish(
              information: information,
              playbackState: isPlaying ? .playing : .paused,
              application: application,
              bundleIdentifier: nil,
              capabilities: capabilities,
              selectedClient: nil,
              generation: generation
            )
          }
        }
      }
    }
  }

  private func refreshInactiveClient(
    runtime: MediaRemoteRuntime,
    generation: UInt64
  ) {
    runtime.getNowPlayingClient(on: queue) { [weak self] systemSelectedClient in
      guard let self,
        self.isCurrent(runtime: runtime, generation: generation)
      else {
        return
      }
      runtime.getNowPlayingClients(on: self.queue) { [weak self] discovered in
        guard let self,
          self.isCurrent(runtime: runtime, generation: generation)
        else {
          return
        }

        var clients = discovered
        if let systemSelectedClient,
          !clients.contains(where: { $0 === systemSelectedClient })
        {
          clients.insert(systemSelectedClient, at: 0)
        }
        let systemSelectedIndex = systemSelectedClient.flatMap { selected in
          clients.firstIndex(where: { $0 === selected })
        }
        let previouslySelectedIndex = self.currentClient.flatMap { previous in
          clients.firstIndex(where: { $0 === previous })
        }
        let orderedClients =
          MediaRemoteClientSelectionPolicy.orderedIndices(
            clientCount: clients.count,
            systemSelectedIndex: systemSelectedIndex,
            previouslySelectedIndex: previouslySelectedIndex
          ).map { clients[$0] }

        self.resolveInactiveClient(
          in: orderedClients,
          at: 0,
          runtime: runtime,
          generation: generation
        )
      }
    }
  }

  private func resolveInactiveClient(
    in clients: [AnyObject],
    at index: Int,
    runtime: MediaRemoteRuntime,
    generation: UInt64
  ) {
    guard index < clients.count else {
      resolveDormantPlayer(
        runtime: runtime,
        generation: generation
      )
      return
    }

    let client = clients[index]
    guard
      let bundleIdentifier = runtime.bundleIdentifier(for: client),
      let application = hostRunningApplications.first(where: {
        $0.bundleIdentifier == bundleIdentifier
      })
    else {
      resolveInactiveClient(
        in: clients,
        at: index + 1,
        runtime: runtime,
        generation: generation
      )
      return
    }

    runtime.getSupportedCapabilities(
      for: client,
      on: queue
    ) { [weak self] capabilities in
      guard let self,
        self.isCurrent(runtime: runtime, generation: generation)
      else {
        return
      }
      guard capabilities.contains(.playPause) else {
        self.resolveInactiveClient(
          in: clients,
          at: index + 1,
          runtime: runtime,
          generation: generation
        )
        return
      }

      runtime.getNowPlayingInfo(for: client, on: self.queue) {
        [weak self] information in
        guard let self,
          self.isCurrent(runtime: runtime, generation: generation)
        else {
          return
        }
        let information = information ?? [:]
        let playbackRate =
          (information[
            "kMRMediaRemoteNowPlayingInfoPlaybackRate"
          ] as? NSNumber)?.finiteDoubleExcludingBoolean ?? 0
        self.publish(
          information: information,
          playbackState: playbackRate > 0 ? .playing : .paused,
          application: application,
          bundleIdentifier: bundleIdentifier,
          capabilities: capabilities,
          selectedClient: client,
          generation: generation
        )
      }
    }
  }

  private func resolveDormantPlayer(
    runtime: MediaRemoteRuntime,
    generation: UInt64
  ) {
    guard
      let selected = MediaRemoteDormantPlayerPolicy.select(
        from: hostRunningApplications,
        discoveredBundleIdentifiers: discoveredPlayerBundleIdentifiers,
        frontmostBundleIdentifier: hostFrontmostBundleIdentifier,
        previouslySelectedBundleIdentifier: currentSourceBundleIdentifier
      ),
      let client = runtime.createClient(
        processIdentifier: selected.processIdentifier,
        bundleIdentifier: selected.bundleIdentifier
      )
    else {
      publishUnavailable(generation: generation)
      return
    }

    runtime.getNowPlayingInfoForResolvedPlayer(for: client, on: queue) {
      [weak self] information in
      guard let self,
        self.isCurrent(runtime: runtime, generation: generation)
      else {
        return
      }
      let information = information ?? [:]
      let publishInformation: (NSDictionary) -> Void = {
        [weak self] resolvedInformation in
        guard let self,
          self.isCurrent(runtime: runtime, generation: generation)
        else {
          return
        }
        runtime.getSupportedCapabilitiesForResolvedPlayer(
          for: client,
          on: self.queue
        ) {
          [weak self] capabilities in
          guard let self,
            self.isCurrent(runtime: runtime, generation: generation)
          else {
            return
          }
          let playbackRate =
            (resolvedInformation[
              "kMRMediaRemoteNowPlayingInfoPlaybackRate"
            ] as? NSNumber)?.finiteDoubleExcludingBoolean
          self.publish(
            information: resolvedInformation,
            playbackState:
              MediaRemoteDormantPlayerPolicy.playbackState(
                forPlaybackRate: playbackRate
              ),
            application: selected,
            bundleIdentifier: selected.bundleIdentifier,
            capabilities:
              MediaRemoteDormantPlayerPolicy.resolvedCapabilities(
                reported: capabilities
              ),
            selectedClient: client,
            generation: generation
          )
        }
      }
      guard information.count > 0 else {
        publishInformation(information)
        return
      }
      runtime.getNowPlayingArtworkForResolvedPlayer(
        for: client,
        on: self.queue
      ) { [weak self] artwork in
        guard let self,
          self.isCurrent(runtime: runtime, generation: generation)
        else {
          return
        }
        guard let artworkData = artwork.data else {
          publishInformation(information)
          return
        }
        let enrichedInformation =
          information.mutableCopy() as? NSMutableDictionary
          ?? NSMutableDictionary(dictionary: information)
        enrichedInformation[
          "kMRMediaRemoteNowPlayingInfoArtworkData"
        ] = artworkData
        if let mimeType = artwork.mimeType {
          enrichedInformation[
            "kMRMediaRemoteNowPlayingInfoArtworkMIMEType"
          ] = mimeType
        }
        publishInformation(enrichedInformation)
      }
    }
  }

  private func publish(
    information: NSDictionary,
    playbackState: MediaPlaybackState,
    application: MediaRemoteRunningApplication?,
    bundleIdentifier suppliedBundleIdentifier: String?,
    capabilities: Set<MediaCapability>,
    selectedClient: AnyObject?,
    generation: UInt64
  ) {
    guard generation == monitoringGeneration,
      let monitoringClientGeneration,
      acceptsClient(monitoringClientGeneration)
    else {
      return
    }
    pendingAvailabilityRecovery?.cancel()
    pendingAvailabilityRecovery = nil
    availabilityRecoveryPolicy.reset()
    let bundleIdentifier = MediaSession.bounded(
      suppliedBundleIdentifier ?? application?.bundleIdentifier,
      maximum: MediaSession.maximumBundleIdentifierBytes
    )
    let uniqueIdentifier = MediaSession.bounded(
      information[
        "kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
      ] as? String,
      maximum: MediaSession.maximumMetadataBytes
    )
    let sessionCandidate =
      bundleIdentifier.map { bundleIdentifier in
        if let application {
          return "\(bundleIdentifier):\(application.processIdentifier)"
        }
        return "media-client:\(bundleIdentifier)"
      } ?? uniqueIdentifier.map { "media:\($0)" }
      ?? "media:global"
    guard
      let sessionID = MediaSession.bounded(
        sessionCandidate,
        maximum: MediaSession.maximumSessionIDBytes
      )
    else {
      publishUnavailable(generation: generation)
      return
    }
    let title = boundedMetadataString(
      information["kMRMediaRemoteNowPlayingInfoTitle"]
    )
    let artist = boundedMetadataString(
      information["kMRMediaRemoteNowPlayingInfoArtist"]
    )
    let album = boundedMetadataString(
      information["kMRMediaRemoteNowPlayingInfoAlbum"]
    )
    let contentIdentity = ContentIdentity(
      sessionID: sessionID,
      uniqueIdentifier: uniqueIdentifier,
      title: title,
      artist: artist,
      album: album
    )
    let didContentChange = currentContentIdentity != contentIdentity
    if contentIdentity.hasMetadata {
      pendingDormantUpgrade?.cancel()
      pendingDormantUpgrade = nil
    }
    if didContentChange {
      contentRevision &+= 1
      currentContentIdentity = contentIdentity
    }
    currentSessionID = sessionID
    currentClient = selectedClient
    currentSourceBundleIdentifier = bundleIdentifier
    if let bundleIdentifier, capabilities.contains(.playPause) {
      discoveredPlayerBundleIdentifiers.insert(bundleIdentifier)
    }
    if capabilities != currentCapabilities {
      currentCapabilities = capabilities
      currentCapabilityRevision &+= 1
    }

    var propertyList: [String: Any] = [
      "protocolVersion": NSNumber(
        value: MediaCompatibilityReport.protocolVersion
      ),
      "isPresent": true,
      "sessionID": sessionID,
      "playbackState": playbackState.rawValue,
      "capabilityRevision": NSNumber(value: currentCapabilityRevision),
      "contentRevision": NSNumber(value: contentRevision),
      "capabilities": currentCapabilities.map(\.rawValue).sorted(),
    ]
    propertyList["title"] = title
    propertyList["artist"] = artist
    propertyList["album"] = album
    propertyList["duration"] = nonnegativeFiniteNumber(
      information["kMRMediaRemoteNowPlayingInfoDuration"]
    )
    let progress = nonnegativeFiniteNumber(
      information["kMRMediaRemoteNowPlayingInfoElapsedTime"]
    )
    propertyList["progress"] = progress
    if progress != nil {
      propertyList["progressSampleTimestamp"] = NSNumber(
        value: Date().timeIntervalSince1970
      )
    }
    if let bundleIdentifier {
      propertyList["sourceBundleIdentifier"] = bundleIdentifier
    }
    if let name = MediaSession.bounded(
      application?.applicationName,
      maximum: MediaSession.maximumApplicationNameBytes
    ) {
      propertyList["applicationName"] = name
    }
    if let shareURL = MediaSession.bounded(
      information[
        "kMRMediaRemoteNowPlayingInfoExternalContentIdentifier"
      ] as? String,
      maximum: 2_048
    ) {
      propertyList["publicShareURL"] = shareURL
    }
    appendArtworkUpdate(
      from: information,
      didContentChange: didContentChange,
      to: &propertyList
    )
    propertyList["artworkRevision"] = NSNumber(value: artworkRevision)
    propertyList = propertyList.compactMapValues { $0 }
    client?.mediaRemoteDidUpdate(propertyList as NSDictionary)
  }

  private func publishUnavailable(generation: UInt64) {
    guard generation == monitoringGeneration,
      let monitoringClientGeneration,
      acceptsClient(monitoringClientGeneration)
    else {
      return
    }
    currentSessionID = nil
    currentClient = nil
    currentSourceBundleIdentifier = nil
    currentContentIdentity = nil
    currentCapabilities = []
    client?.mediaRemoteDidUpdate([
      "protocolVersion": NSNumber(
        value: MediaCompatibilityReport.protocolVersion
      ),
      "isPresent": false,
      "contentRevision": NSNumber(value: contentRevision),
      "artworkRevision": NSNumber(value: artworkRevision),
    ])
    scheduleAvailabilityRecovery(generation: generation)
  }

  private func boundedMetadataString(_ value: Any?) -> String? {
    MediaSession.bounded(
      value as? String,
      maximum: MediaSession.maximumMetadataBytes
    )
  }

  private func nonnegativeFiniteNumber(_ value: Any?) -> NSNumber? {
    guard let number = value as? NSNumber,
      let double = number.finiteDoubleExcludingBoolean,
      double >= 0
    else {
      return nil
    }
    return NSNumber(value: double)
  }

  private func appendArtworkUpdate(
    from information: NSDictionary,
    didContentChange: Bool,
    to propertyList: inout [String: Any]
  ) {
    let artwork =
      (information[
        "kMRMediaRemoteNowPlayingInfoArtworkData"
      ] as? Data).flatMap {
        $0.isEmpty || $0.count > MediaSession.maximumArtworkBytes ? nil : $0
      }
    let mimeType = MediaSession.bounded(
      information[
        "kMRMediaRemoteNowPlayingInfoArtworkMIMEType"
      ] as? String,
      maximum: MediaSession.maximumMimeTypeBytes
    )
    guard let artwork else {
      propertyList["artworkUpdate"] =
        didContentChange
        ? MediaArtworkWireUpdate.clear.rawValue
        : MediaArtworkWireUpdate.unchanged.rawValue
      if didContentChange {
        if currentArtworkData != nil || currentArtworkMIMEType != nil {
          artworkRevision &+= 1
        }
        currentArtworkData = nil
        currentArtworkMIMEType = nil
      }
      return
    }
    guard artwork != currentArtworkData || mimeType != currentArtworkMIMEType else {
      propertyList["artworkUpdate"] =
        MediaArtworkWireUpdate.unchanged.rawValue
      return
    }
    currentArtworkData = artwork
    currentArtworkMIMEType = mimeType
    artworkRevision &+= 1
    propertyList["artworkUpdate"] = MediaArtworkWireUpdate.replace.rawValue
    propertyList["artworkData"] = artwork
    propertyList["artworkMIMEType"] = mimeType
  }

  private func stopMonitoringOnQueue() {
    monitoringGeneration &+= 1
    pendingRefresh?.cancel()
    pendingRefresh = nil
    pendingDormantUpgrade?.cancel()
    pendingDormantUpgrade = nil
    pendingAvailabilityRecovery?.cancel()
    pendingAvailabilityRecovery = nil
    availabilityRecoveryPolicy.reset()
    observerTokens.forEach(NotificationCenter.default.removeObserver)
    observerTokens = []
    runtime?.unregisterNotifications()
    runtime = nil
    monitoringClientGeneration = nil
    currentSessionID = nil
    currentClient = nil
    currentSourceBundleIdentifier = nil
    currentContentIdentity = nil
    currentCapabilities = []
    currentCapabilityRevision = 0
    currentArtworkData = nil
    currentArtworkMIMEType = nil
    hostRunningApplications = []
    hostFrontmostBundleIdentifier = nil
  }

  private func isCurrent(
    runtime: MediaRemoteRuntime,
    generation: UInt64
  ) -> Bool {
    guard generation == monitoringGeneration, self.runtime === runtime,
      let monitoringClientGeneration
    else {
      return false
    }
    return acceptsClient(monitoringClientGeneration)
  }

  private func currentClientGeneration() -> UInt64? {
    clientStateLock.withLock {
      activeClientGeneration
    }
  }

  private func acceptsClient(_ generation: UInt64) -> Bool {
    clientStateLock.withLock {
      activeClientGeneration == generation
    }
  }
}

private struct ContentIdentity: Equatable {
  let sessionID: String
  let uniqueIdentifier: String?
  let title: String?
  let artist: String?
  let album: String?

  var hasMetadata: Bool {
    uniqueIdentifier != nil || title != nil || artist != nil || album != nil
  }
}

private struct ResolvedArtwork {
  let data: Data?
  let mimeType: String?
}

private final class MediaRemoteRuntime {
  private typealias CreateClientFunction =
    @convention(c) (Int32, CFString) -> Unmanaged<AnyObject>?
  private typealias SendCommandFunction =
    @convention(c) (Int32, UnsafeRawPointer?) -> UInt8
  private typealias ClientCommandCompletion =
    @convention(block) (UInt8) -> Void
  private typealias SendCommandToClientFunction =
    @convention(c) (
      Int32,
      AnyObject?,
      AnyObject,
      AnyObject,
      AnyObject?,
      DispatchQueue,
      ClientCommandCompletion
    ) -> Void
  private typealias SetElapsedTimeFunction =
    @convention(c) (Double) -> Void
  private typealias RegisterFunction =
    @convention(c) (DispatchQueue) -> Void
  private typealias UnregisterFunction =
    @convention(c) () -> Void
  private typealias InformationCompletion =
    @convention(block) (CFDictionary?) -> Void
  private typealias InformationFunction =
    @convention(c) (DispatchQueue, InformationCompletion) -> Void
  private typealias ClientCompletion =
    @convention(block) (AnyObject?) -> Void
  private typealias ClientsCompletion =
    @convention(block) (NSArray?) -> Void
  private typealias ClientFunction =
    @convention(c) (DispatchQueue, ClientCompletion) -> Void
  private typealias ClientsFunction =
    @convention(c) (DispatchQueue, ClientsCompletion) -> Void
  private typealias LocalOriginFunction =
    @convention(c) () -> Unmanaged<AnyObject>?
  private typealias InformationForClientFunction =
    @convention(c) (
      AnyObject,
      AnyObject,
      Int32,
      DispatchQueue,
      InformationCompletion
    ) -> Void
  private typealias PlayerCompletion =
    @convention(block) (AnyObject?) -> Void
  private typealias PlayerForClientFunction =
    @convention(c) (
      AnyObject,
      AnyObject,
      DispatchQueue,
      PlayerCompletion
    ) -> Void
  private typealias PlayerPathCreateFunction =
    @convention(c) (
      AnyObject,
      AnyObject,
      AnyObject
    ) -> Unmanaged<AnyObject>?
  private typealias InformationForPlayerFunction =
    @convention(c) (
      AnyObject,
      UInt8,
      DispatchQueue,
      InformationCompletion
    ) -> Void
  private typealias CommandsCompletion =
    @convention(block) (NSArray?) -> Void
  private typealias CommandsForClientFunction =
    @convention(c) (
      AnyObject,
      AnyObject,
      DispatchQueue,
      CommandsCompletion
    ) -> Void
  private typealias CommandsForPlayerFunction =
    @convention(c) (
      AnyObject,
      DispatchQueue,
      CommandsCompletion
    ) -> Void
  private typealias CreatePlaybackQueueRequestFunction =
    @convention(c) () -> Unmanaged<AnyObject>?
  private typealias SetPlaybackQueueRequestFlagFunction =
    @convention(c) (AnyObject, UInt8) -> Void
  private typealias PlaybackQueueCompletion =
    @convention(block) (AnyObject?, CFError?) -> Void
  private typealias RequestPlaybackQueueFunction =
    @convention(c) (
      AnyObject,
      AnyObject,
      DispatchQueue,
      PlaybackQueueCompletion
    ) -> Void
  private typealias ContentItemAtOffsetFunction =
    @convention(c) (AnyObject, Int) -> Unmanaged<AnyObject>?
  private typealias ContentItemArtworkDataFunction =
    @convention(c) (AnyObject) -> Unmanaged<CFData>?
  private typealias ContentItemArtworkMIMETypeFunction =
    @convention(c) (AnyObject) -> Unmanaged<CFString>?
  private typealias ClientIdentifierFunction =
    @convention(c) (UnsafeRawPointer?) -> Unmanaged<CFString>?
  private typealias PlayingCompletion = @convention(block) (UInt8) -> Void
  private typealias PlayingFunction =
    @convention(c) (DispatchQueue, PlayingCompletion) -> Void
  private typealias PIDCompletion = @convention(block) (Int32) -> Void
  private typealias PIDFunction =
    @convention(c) (DispatchQueue, PIDCompletion) -> Void

  private let handle: UnsafeMutableRawPointer
  private let createClientFunction: CreateClientFunction
  private let sendCommandFunction: SendCommandFunction
  private let sendCommandToClientFunction: SendCommandToClientFunction
  private let registerFunction: RegisterFunction
  private let unregisterFunction: UnregisterFunction
  private let informationFunction: InformationFunction
  private let clientFunction: ClientFunction
  private let clientsFunction: ClientsFunction
  private let localOriginFunction: LocalOriginFunction
  private let informationForClientFunction: InformationForClientFunction
  private let playerForClientFunction: PlayerForClientFunction
  private let playerPathCreateFunction: PlayerPathCreateFunction
  private let informationForPlayerFunction: InformationForPlayerFunction
  private let commandsForClientFunction: CommandsForClientFunction
  private let commandsForPlayerFunction: CommandsForPlayerFunction
  private let createPlaybackQueueRequestFunction:
    CreatePlaybackQueueRequestFunction
  private let setPlaybackQueueRequestIncludeArtworkFunction:
    SetPlaybackQueueRequestFlagFunction
  private let setPlaybackQueueRequestReturnAssetsFunction:
    SetPlaybackQueueRequestFlagFunction
  private let requestPlaybackQueueFunction: RequestPlaybackQueueFunction
  private let contentItemAtOffsetFunction: ContentItemAtOffsetFunction
  private let contentItemArtworkDataFunction: ContentItemArtworkDataFunction
  private let contentItemArtworkMIMETypeFunction:
    ContentItemArtworkMIMETypeFunction
  private let clientBundleIdentifierFunction: ClientIdentifierFunction
  private let clientParentBundleIdentifierFunction: ClientIdentifierFunction
  private let playingFunction: PlayingFunction
  private let pidFunction: PIDFunction
  private let setElapsedTimeFunction: SetElapsedTimeFunction?
  private let supportedCommands: SupportedCommandsRuntime

  init?(frameworkPath: String) {
    guard
      let handle = dlopen(
        frameworkPath,
        RTLD_LAZY | RTLD_LOCAL
      )
    else {
      return nil
    }
    guard
      let createClientFunction: CreateClientFunction = Self.resolve(
        "MRNowPlayingClientCreate",
        in: handle
      ),
      let sendCommandFunction: SendCommandFunction = Self.resolve(
        "MRMediaRemoteSendCommand",
        in: handle
      ),
      let sendCommandToClientFunction: SendCommandToClientFunction =
        Self.resolve(
          "MRMediaRemoteSendCommandToClient",
          in: handle
        ),
      let registerFunction: RegisterFunction = Self.resolve(
        "MRMediaRemoteRegisterForNowPlayingNotifications",
        in: handle
      ),
      let unregisterFunction: UnregisterFunction = Self.resolve(
        "MRMediaRemoteUnregisterForNowPlayingNotifications",
        in: handle
      ),
      let informationFunction: InformationFunction = Self.resolve(
        "MRMediaRemoteGetNowPlayingInfo",
        in: handle
      ),
      let clientFunction: ClientFunction = Self.resolve(
        "MRMediaRemoteGetNowPlayingClient",
        in: handle
      ),
      let clientsFunction: ClientsFunction = Self.resolve(
        "MRMediaRemoteGetNowPlayingClients",
        in: handle
      ),
      let localOriginFunction: LocalOriginFunction = Self.resolve(
        "MRMediaRemoteGetLocalOrigin",
        in: handle
      ),
      let informationForClientFunction: InformationForClientFunction =
        Self.resolve(
          "MRMediaRemoteGetNowPlayingInfoForClient",
          in: handle
        ),
      let playerForClientFunction: PlayerForClientFunction =
        Self.resolve(
          "MRMediaRemoteGetNowPlayingPlayerForClient",
          in: handle
        ),
      let playerPathCreateFunction: PlayerPathCreateFunction =
        Self.resolve(
          "MRNowPlayingPlayerPathCreate",
          in: handle
        ),
      let informationForPlayerFunction: InformationForPlayerFunction =
        Self.resolve(
          "MRMediaRemoteGetNowPlayingInfoForPlayer",
          in: handle
        ),
      let commandsForClientFunction: CommandsForClientFunction =
        Self.resolve(
          "MRMediaRemoteGetSupportedCommandsForClient",
          in: handle
        ),
      let commandsForPlayerFunction: CommandsForPlayerFunction =
        Self.resolve(
          "MRMediaRemoteGetSupportedCommandsForPlayer",
          in: handle
        ),
      let createPlaybackQueueRequestFunction:
        CreatePlaybackQueueRequestFunction =
        Self.resolve(
          "MRPlaybackQueueRequestCreateDefault",
          in: handle
        ),
      let setPlaybackQueueRequestIncludeArtworkFunction:
        SetPlaybackQueueRequestFlagFunction =
        Self.resolve(
          "MRPlaybackQueueRequestSetIncludeArtwork",
          in: handle
        ),
      let setPlaybackQueueRequestReturnAssetsFunction:
        SetPlaybackQueueRequestFlagFunction =
        Self.resolve(
          "MRPlaybackQueueRequestSetReturnContentItemAssetsInUserCompletion",
          in: handle
        ),
      let requestPlaybackQueueFunction: RequestPlaybackQueueFunction =
        Self.resolve(
          "MRMediaRemoteRequestNowPlayingPlaybackQueueForPlayerSync",
          in: handle
        ),
      let contentItemAtOffsetFunction: ContentItemAtOffsetFunction =
        Self.resolve(
          "MRPlaybackQueueGetContentItemAtOffset",
          in: handle
        ),
      let contentItemArtworkDataFunction: ContentItemArtworkDataFunction =
        Self.resolve(
          "MRContentItemGetArtworkData",
          in: handle
        ),
      let contentItemArtworkMIMETypeFunction:
        ContentItemArtworkMIMETypeFunction =
        Self.resolve(
          "MRContentItemGetArtworkMIMEType",
          in: handle
        ),
      let clientBundleIdentifierFunction: ClientIdentifierFunction =
        Self.resolve(
          "MRNowPlayingClientGetBundleIdentifier",
          in: handle
        ),
      let clientParentBundleIdentifierFunction: ClientIdentifierFunction =
        Self.resolve(
          "MRNowPlayingClientGetParentAppBundleIdentifier",
          in: handle
        ),
      let playingFunction: PlayingFunction = Self.resolve(
        "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
        in: handle
      ),
      let pidFunction: PIDFunction = Self.resolve(
        "MRMediaRemoteGetNowPlayingApplicationPID",
        in: handle
      ),
      let supportedCommands = SupportedCommandsRuntime(handle: handle)
    else {
      dlclose(handle)
      return nil
    }

    self.handle = handle
    self.createClientFunction = createClientFunction
    self.sendCommandFunction = sendCommandFunction
    self.sendCommandToClientFunction = sendCommandToClientFunction
    self.registerFunction = registerFunction
    self.unregisterFunction = unregisterFunction
    self.informationFunction = informationFunction
    self.clientFunction = clientFunction
    self.clientsFunction = clientsFunction
    self.localOriginFunction = localOriginFunction
    self.informationForClientFunction = informationForClientFunction
    self.playerForClientFunction = playerForClientFunction
    self.playerPathCreateFunction = playerPathCreateFunction
    self.informationForPlayerFunction = informationForPlayerFunction
    self.commandsForClientFunction = commandsForClientFunction
    self.commandsForPlayerFunction = commandsForPlayerFunction
    self.createPlaybackQueueRequestFunction =
      createPlaybackQueueRequestFunction
    self.setPlaybackQueueRequestIncludeArtworkFunction =
      setPlaybackQueueRequestIncludeArtworkFunction
    self.setPlaybackQueueRequestReturnAssetsFunction =
      setPlaybackQueueRequestReturnAssetsFunction
    self.requestPlaybackQueueFunction = requestPlaybackQueueFunction
    self.contentItemAtOffsetFunction = contentItemAtOffsetFunction
    self.contentItemArtworkDataFunction = contentItemArtworkDataFunction
    self.contentItemArtworkMIMETypeFunction =
      contentItemArtworkMIMETypeFunction
    self.clientBundleIdentifierFunction = clientBundleIdentifierFunction
    self.clientParentBundleIdentifierFunction =
      clientParentBundleIdentifierFunction
    self.playingFunction = playingFunction
    self.pidFunction = pidFunction
    self.supportedCommands = supportedCommands

    let elapsed: SetElapsedTimeFunction? = Self.resolve(
      "MRMediaRemoteSetElapsedTime",
      in: handle
    )
    setElapsedTimeFunction = elapsed

  }

  deinit {
    dlclose(handle)
  }

  func registerNotifications(on queue: DispatchQueue) {
    registerFunction(queue)
  }

  func unregisterNotifications() {
    unregisterFunction()
  }

  func createClient(
    processIdentifier: Int32,
    bundleIdentifier: String
  ) -> AnyObject? {
    createClientFunction(
      processIdentifier,
      bundleIdentifier as CFString
    )?.takeRetainedValue()
  }

  func getNowPlayingInfo(
    on queue: DispatchQueue,
    completion: @escaping (NSDictionary?) -> Void
  ) {
    let block: InformationCompletion = { information in
      completion(information as NSDictionary?)
    }
    informationFunction(queue, block)
  }

  func getNowPlayingClient(
    on queue: DispatchQueue,
    completion: @escaping (AnyObject?) -> Void
  ) {
    let block: ClientCompletion = completion
    clientFunction(queue, block)
  }

  func getNowPlayingClients(
    on queue: DispatchQueue,
    completion: @escaping ([AnyObject]) -> Void
  ) {
    let block: ClientsCompletion = { clients in
      completion(clients as? [AnyObject] ?? [])
    }
    clientsFunction(queue, block)
  }

  func getNowPlayingInfo(
    for client: AnyObject,
    on queue: DispatchQueue,
    completion: @escaping (NSDictionary?) -> Void
  ) {
    guard let origin = localOriginFunction()?.takeUnretainedValue() else {
      completion(nil)
      return
    }
    let block: InformationCompletion = { information in
      completion(information as NSDictionary?)
    }
    informationForClientFunction(
      client,
      origin,
      1,
      queue,
      block
    )
  }

  func getNowPlayingInfoForResolvedPlayer(
    for client: AnyObject,
    on queue: DispatchQueue,
    completion: @escaping (NSDictionary?) -> Void
  ) {
    guard let origin = localOriginFunction()?.takeUnretainedValue() else {
      completion(nil)
      return
    }
    let completion = UncheckedClosure(completion)
    let block: PlayerCompletion = {
      [playerPathCreateFunction, informationForPlayerFunction] player in
      guard
        let player,
        let playerPath = playerPathCreateFunction(
          origin,
          client,
          player
        )?.takeRetainedValue()
      else {
        queue.async {
          completion.call(nil)
        }
        return
      }
      let informationBlock: InformationCompletion = { information in
        completion.call(information as NSDictionary?)
      }
      informationForPlayerFunction(
        playerPath,
        1,
        queue,
        informationBlock
      )
    }
    playerForClientFunction(client, origin, queue, block)
  }

  func bundleIdentifier(for client: AnyObject) -> String? {
    let pointer = Unmanaged.passUnretained(client).toOpaque()
    let parentIdentifier =
      clientParentBundleIdentifierFunction(pointer)?
      .takeUnretainedValue() as String?
    let clientIdentifier =
      clientBundleIdentifierFunction(pointer)?
      .takeUnretainedValue() as String?
    return MediaSession.bounded(
      parentIdentifier ?? clientIdentifier,
      maximum: MediaSession.maximumBundleIdentifierBytes
    )
  }

  func getIsPlaying(
    on queue: DispatchQueue,
    completion: @escaping (Bool) -> Void
  ) {
    let block: PlayingCompletion = { value in
      completion(value != 0)
    }
    playingFunction(queue, block)
  }

  func getApplicationPID(
    on queue: DispatchQueue,
    completion: @escaping (Int32) -> Void
  ) {
    let block: PIDCompletion = completion
    pidFunction(queue, block)
  }

  func getSupportedCapabilities(
    on queue: DispatchQueue,
    completion: @escaping (Set<MediaCapability>) -> Void
  ) {
    let independentTransports: Set<MediaCapability> =
      setElapsedTimeFunction == nil ? [] : [.seek]
    supportedCommands.getCapabilities(on: queue) { capabilities in
      completion(capabilities.union(independentTransports))
    }
  }

  func getSupportedCapabilities(
    for client: AnyObject,
    on queue: DispatchQueue,
    completion: @escaping (Set<MediaCapability>) -> Void
  ) {
    guard let origin = localOriginFunction()?.takeUnretainedValue() else {
      completion([])
      return
    }
    let completion = UncheckedClosure(completion)
    let block: CommandsCompletion = { [supportedCommands] commands in
      let capabilities = supportedCommands.capabilities(from: commands)
      queue.async {
        completion.call(capabilities)
      }
    }
    commandsForClientFunction(client, origin, queue, block)
  }

  func getSupportedCapabilitiesForResolvedPlayer(
    for client: AnyObject,
    on queue: DispatchQueue,
    completion: @escaping (Set<MediaCapability>) -> Void
  ) {
    let completion = UncheckedClosure(completion)
    resolvePlayerPath(for: client, on: queue) {
      [commandsForPlayerFunction, supportedCommands] playerPath in
      guard let playerPath else {
        completion.call([])
        return
      }
      let block: CommandsCompletion = { commands in
        completion.call(supportedCommands.capabilities(from: commands))
      }
      commandsForPlayerFunction(playerPath, queue, block)
    }
  }

  func getNowPlayingArtworkForResolvedPlayer(
    for client: AnyObject,
    on queue: DispatchQueue,
    completion: @escaping (ResolvedArtwork) -> Void
  ) {
    let completion = UncheckedClosure(completion)
    resolvePlayerPath(for: client, on: queue) {
      [
        createPlaybackQueueRequestFunction,
        setPlaybackQueueRequestIncludeArtworkFunction,
        setPlaybackQueueRequestReturnAssetsFunction,
        requestPlaybackQueueFunction,
        contentItemAtOffsetFunction,
        contentItemArtworkDataFunction,
        contentItemArtworkMIMETypeFunction,
      ] playerPath in
      guard
        let playerPath,
        let request =
          createPlaybackQueueRequestFunction()?.takeRetainedValue()
      else {
        completion.call(.init(data: nil, mimeType: nil))
        return
      }
      setPlaybackQueueRequestIncludeArtworkFunction(request, 1)
      setPlaybackQueueRequestReturnAssetsFunction(request, 1)
      let artworkRequestSelectors = [
        NSSelectorFromString("setArtworkWidth:"),
        NSSelectorFromString("setArtworkHeight:"),
        NSSelectorFromString("setCachingPolicy:"),
        NSSelectorFromString("setLegacyNowPlayingInfoRequest:"),
      ]
      if let requestObject = request as? NSObject,
        artworkRequestSelectors.allSatisfy({
          requestObject.responds(to: $0)
        })
      {
        requestObject.setValue(
          NSNumber(value: 512),
          forKey: "artworkWidth"
        )
        requestObject.setValue(
          NSNumber(value: 512),
          forKey: "artworkHeight"
        )
        requestObject.setValue(
          NSNumber(value: 2),
          forKey: "cachingPolicy"
        )
        requestObject.setValue(
          true,
          forKey: "legacyNowPlayingInfoRequest"
        )
      }
      let block: PlaybackQueueCompletion = { playbackQueue, _ in
        guard
          let playbackQueue,
          let contentItem =
            contentItemAtOffsetFunction(
              playbackQueue,
              0
            )?.takeUnretainedValue()
        else {
          completion.call(.init(data: nil, mimeType: nil))
          return
        }
        completion.call(
          .init(
            data:
              contentItemArtworkDataFunction(contentItem)?
              .takeUnretainedValue() as Data?,
            mimeType:
              contentItemArtworkMIMETypeFunction(contentItem)?
              .takeUnretainedValue() as String?
          )
        )
      }
      requestPlaybackQueueFunction(request, playerPath, queue, block)
    }
  }

  func send(
    command: MediaRemoteCommandName,
    value: NSNumber?,
    to client: AnyObject?,
    on queue: DispatchQueue,
    completion: @escaping (Bool) -> Void
  ) {
    guard let client else {
      completion(sendGlobal(command: command, value: value))
      return
    }
    guard command != .seek,
      let origin = localOriginFunction()?.takeUnretainedValue()
    else {
      completion(false)
      return
    }
    let block: ClientCommandCompletion = { status in
      completion(MediaRemoteClientCommandStatus.isAccepted(status))
    }
    sendCommandToClientFunction(
      command.commandValue,
      nil,
      origin,
      client,
      nil,
      queue,
      block
    )
  }

  private func sendGlobal(
    command: MediaRemoteCommandName,
    value: NSNumber?
  ) -> Bool {
    switch command {
    case .seek:
      guard let value, let setElapsedTimeFunction,
        value.doubleValue.isFinite, value.doubleValue >= 0
      else {
        return false
      }
      setElapsedTimeFunction(value.doubleValue)
      return true
    default:
      return sendCommandFunction(command.commandValue, nil) != 0
    }
  }

  private func resolvePlayerPath(
    for client: AnyObject,
    on queue: DispatchQueue,
    completion: @escaping (AnyObject?) -> Void
  ) {
    guard let origin = localOriginFunction()?.takeUnretainedValue() else {
      completion(nil)
      return
    }
    let completion = UncheckedClosure(completion)
    let block: PlayerCompletion = { [playerPathCreateFunction] player in
      let playerPath = player.flatMap {
        playerPathCreateFunction(
          origin,
          client,
          $0
        )?.takeRetainedValue()
      }
      completion.call(playerPath)
    }
    playerForClientFunction(client, origin, queue, block)
  }

  private static func resolve<Function>(
    _ symbol: String,
    in handle: UnsafeMutableRawPointer
  ) -> Function? {
    guard let pointer = dlsym(handle, symbol) else {
      return nil
    }
    return unsafeBitCast(pointer, to: Function.self)
  }
}

private final class SupportedCommandsRuntime {
  private typealias CommandsCompletion =
    @convention(block) (NSArray?) -> Void
  private typealias CopySupportedCommandsFunction =
    @convention(c) (DispatchQueue, CommandsCompletion) -> Void
  private typealias CommandInfoGetCommandFunction =
    @convention(c) (UnsafeRawPointer) -> Int32
  private typealias CommandInfoGetEnabledFunction =
    @convention(c) (UnsafeRawPointer) -> UInt8

  private let copySupportedCommands: CopySupportedCommandsFunction
  private let getCommand: CommandInfoGetCommandFunction
  private let getEnabled: CommandInfoGetEnabledFunction

  init?(handle: UnsafeMutableRawPointer) {
    guard
      let copySupportedCommands: CopySupportedCommandsFunction = Self.resolve(
        "MRMediaRemoteCopySupportedCommands",
        in: handle
      ),
      let getCommand: CommandInfoGetCommandFunction = Self.resolve(
        "MRMediaRemoteCommandInfoGetCommand",
        in: handle
      ),
      let getEnabled: CommandInfoGetEnabledFunction = Self.resolve(
        "MRMediaRemoteCommandInfoGetEnabled",
        in: handle
      )
    else {
      return nil
    }
    self.copySupportedCommands = copySupportedCommands
    self.getCommand = getCommand
    self.getEnabled = getEnabled
  }

  func getCapabilities(
    on queue: DispatchQueue,
    completion: @escaping (Set<MediaCapability>) -> Void
  ) {
    let getCommand = getCommand
    let getEnabled = getEnabled
    let completion = UncheckedClosure(completion)
    let block: CommandsCompletion = { commands in
      let capabilities = Self.capabilities(
        from: commands,
        getCommand: getCommand,
        getEnabled: getEnabled
      )
      queue.async {
        completion.call(capabilities)
      }
    }
    copySupportedCommands(queue, block)
  }

  func capabilities(from commands: NSArray?) -> Set<MediaCapability> {
    Self.capabilities(
      from: commands,
      getCommand: getCommand,
      getEnabled: getEnabled
    )
  }

  private static func capabilities(
    from commands: NSArray?,
    getCommand: CommandInfoGetCommandFunction,
    getEnabled: CommandInfoGetEnabledFunction
  ) -> Set<MediaCapability> {
    let enabledCommands =
      (commands as? [AnyObject] ?? []).compactMap { commandInfo -> Int32? in
        let pointer = Unmanaged.passUnretained(commandInfo).toOpaque()
        guard getEnabled(pointer) != 0 else {
          return nil
        }
        return getCommand(pointer)
      }
    return MediaRemoteCapabilityPolicy.capabilities(
      forEnabledCommands: enabledCommands,
      independentTransports: []
    )
  }

  private static func resolve<Function>(
    _ symbol: String,
    in handle: UnsafeMutableRawPointer
  ) -> Function? {
    guard let pointer = dlsym(handle, symbol) else {
      return nil
    }
    return unsafeBitCast(pointer, to: Function.self)
  }
}

private final class UncheckedClosure<Input>: @unchecked Sendable {
  private let body: (Input) -> Void

  init(_ body: @escaping (Input) -> Void) {
    self.body = body
  }

  func call(_ input: Input) {
    body(input)
  }
}
