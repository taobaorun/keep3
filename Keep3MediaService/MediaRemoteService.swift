import AppKit
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
  private var monitoringGeneration: UInt64 = 0
  private var monitoringClientGeneration: UInt64?
  private var contentRevision: UInt64 = 0
  private var currentSessionID: String?
  private var currentContentIdentity: ContentIdentity?
  private var currentCapabilities: Set<MediaCapability> = []
  private var currentCapabilityRevision: UInt64 = 0
  private var currentArtworkData: Data?
  private var currentArtworkMIMEType: String?

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

  func startMonitoring(reply: @escaping @Sendable (Bool) -> Void) {
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
      reply(self.runtime?.send(command: command, value: value) ?? false)
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
        self.publishUnavailable(generation: generation)
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
          runtime.getSupportedCapabilities(on: self.queue) {
            [weak self] capabilities in
            guard let self,
              self.isCurrent(runtime: runtime, generation: generation)
            else {
              return
            }
            self.publish(
              information: information,
              isPlaying: isPlaying,
              processIdentifier: pid,
              capabilities: capabilities,
              generation: generation
            )
          }
        }
      }
    }
  }

  private func publish(
    information: NSDictionary,
    isPlaying: Bool,
    processIdentifier: Int32,
    capabilities: Set<MediaCapability>,
    generation: UInt64
  ) {
    guard generation == monitoringGeneration,
      let monitoringClientGeneration,
      acceptsClient(monitoringClientGeneration)
    else {
      return
    }
    let application =
      processIdentifier > 0
      ? NSRunningApplication(
        processIdentifier: pid_t(processIdentifier)
      ) : nil
    let bundleIdentifier = MediaSession.bounded(
      application?.bundleIdentifier,
      maximum: MediaSession.maximumBundleIdentifierBytes
    )
    let uniqueIdentifier = MediaSession.bounded(
      information[
        "kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
      ] as? String,
      maximum: MediaSession.maximumMetadataBytes
    )
    let sessionCandidate =
      bundleIdentifier.map {
        "\($0):\(processIdentifier)"
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
    if currentContentIdentity != contentIdentity {
      contentRevision &+= 1
      currentContentIdentity = contentIdentity
    }
    currentSessionID = sessionID
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
      "playbackState":
        isPlaying
        ? MediaPlaybackState.playing.rawValue
        : MediaPlaybackState.paused.rawValue,
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
      application?.localizedName,
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
    appendArtworkUpdate(from: information, to: &propertyList)
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
    currentContentIdentity = nil
    currentCapabilities = []
    client?.mediaRemoteDidUpdate([
      "protocolVersion": NSNumber(
        value: MediaCompatibilityReport.protocolVersion
      ),
      "isPresent": false,
      "contentRevision": NSNumber(value: contentRevision),
    ])
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
        currentArtworkData == nil
        ? MediaArtworkWireUpdate.unchanged.rawValue
        : MediaArtworkWireUpdate.clear.rawValue
      currentArtworkData = nil
      currentArtworkMIMEType = nil
      return
    }
    guard artwork != currentArtworkData || mimeType != currentArtworkMIMEType else {
      propertyList["artworkUpdate"] =
        MediaArtworkWireUpdate.unchanged.rawValue
      return
    }
    currentArtworkData = artwork
    currentArtworkMIMEType = mimeType
    propertyList["artworkUpdate"] = MediaArtworkWireUpdate.replace.rawValue
    propertyList["artworkData"] = artwork
    propertyList["artworkMIMEType"] = mimeType
  }

  private func stopMonitoringOnQueue() {
    monitoringGeneration &+= 1
    pendingRefresh?.cancel()
    pendingRefresh = nil
    observerTokens.forEach(NotificationCenter.default.removeObserver)
    observerTokens = []
    runtime?.unregisterNotifications()
    runtime = nil
    monitoringClientGeneration = nil
    currentSessionID = nil
    currentContentIdentity = nil
    currentCapabilities = []
    currentCapabilityRevision = 0
    currentArtworkData = nil
    currentArtworkMIMEType = nil
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
}

private final class MediaRemoteRuntime {
  private typealias SendCommandFunction =
    @convention(c) (Int32, UnsafeRawPointer?) -> UInt8
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
  private typealias PlayingCompletion = @convention(block) (UInt8) -> Void
  private typealias PlayingFunction =
    @convention(c) (DispatchQueue, PlayingCompletion) -> Void
  private typealias PIDCompletion = @convention(block) (Int32) -> Void
  private typealias PIDFunction =
    @convention(c) (DispatchQueue, PIDCompletion) -> Void

  private let handle: UnsafeMutableRawPointer
  private let sendCommandFunction: SendCommandFunction
  private let registerFunction: RegisterFunction
  private let unregisterFunction: UnregisterFunction
  private let informationFunction: InformationFunction
  private let playingFunction: PlayingFunction
  private let pidFunction: PIDFunction
  private let setElapsedTimeFunction: SetElapsedTimeFunction?
  private let supportedCommands: SupportedCommandsRuntime?

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
      let sendCommandFunction: SendCommandFunction = Self.resolve(
        "MRMediaRemoteSendCommand",
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
      let playingFunction: PlayingFunction = Self.resolve(
        "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
        in: handle
      ),
      let pidFunction: PIDFunction = Self.resolve(
        "MRMediaRemoteGetNowPlayingApplicationPID",
        in: handle
      )
    else {
      dlclose(handle)
      return nil
    }

    self.handle = handle
    self.sendCommandFunction = sendCommandFunction
    self.registerFunction = registerFunction
    self.unregisterFunction = unregisterFunction
    self.informationFunction = informationFunction
    self.playingFunction = playingFunction
    self.pidFunction = pidFunction

    let elapsed: SetElapsedTimeFunction? = Self.resolve(
      "MRMediaRemoteSetElapsedTime",
      in: handle
    )
    setElapsedTimeFunction = elapsed

    supportedCommands = SupportedCommandsRuntime(handle: handle)
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

  func getNowPlayingInfo(
    on queue: DispatchQueue,
    completion: @escaping (NSDictionary?) -> Void
  ) {
    let block: InformationCompletion = { information in
      completion(information as NSDictionary?)
    }
    informationFunction(queue, block)
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
    guard let supportedCommands else {
      completion(independentTransports)
      return
    }
    supportedCommands.getCapabilities(on: queue) { capabilities in
      completion(capabilities.union(independentTransports))
    }
  }

  func send(command: MediaRemoteCommandName, value: NSNumber?) -> Bool {
    switch command {
    case .togglePlayPause:
      return sendCommandFunction(2, nil) != 0
    case .next:
      return sendCommandFunction(4, nil) != 0
    case .previous:
      return sendCommandFunction(5, nil) != 0
    case .shuffle:
      return sendCommandFunction(6, nil) != 0
    case .repeatMode:
      return sendCommandFunction(7, nil) != 0
    case .seek:
      guard let value, let setElapsedTimeFunction,
        value.doubleValue.isFinite, value.doubleValue >= 0
      else {
        return false
      }
      setElapsedTimeFunction(value.doubleValue)
      return true
    }
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
      let enabledCommands =
        (commands as? [AnyObject] ?? []).compactMap { commandInfo -> Int32? in
          let pointer = Unmanaged.passUnretained(commandInfo).toOpaque()
          guard getEnabled(pointer) != 0 else {
            return nil
          }
          return getCommand(pointer)
        }
      let capabilities = MediaRemoteCapabilityPolicy.capabilities(
        forEnabledCommands: enabledCommands,
        independentTransports: []
      )
      queue.async {
        completion.call(capabilities)
      }
    }
    copySupportedCommands(queue, block)
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
