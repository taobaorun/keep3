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
  private var client: (any MediaRemoteClientProtocol)?
  private var runtime: MediaRemoteRuntime?
  private var observerTokens: [NSObjectProtocol] = []
  private var pendingRefresh: DispatchWorkItem?
  private var contentRevision: UInt64 = 0
  private var currentSessionID: String?
  private var currentContentIdentity: ContentIdentity?

  func attach(client: any MediaRemoteClientProtocol) {
    self.client = client
  }

  func compatibilityReport(
    reply: @escaping @Sendable (NSDictionary) -> Void
  ) {
    reply(Self.probe().propertyList)
  }

  func startMonitoring(reply: @escaping @Sendable (Bool) -> Void) {
    queue.async { [weak self] in
      guard let self else {
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
      runtime.registerNotifications(on: self.queue)
      self.installObservers()
      self.refresh()
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
    value: NSNumber?,
    reply: @escaping @Sendable (Bool) -> Void
  ) {
    queue.async { [weak self] in
      guard let self, self.currentSessionID == sessionID else {
        reply(false)
        return
      }
      reply(self.runtime?.send(action: action, value: value) ?? false)
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

  private func installObservers() {
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
        self?.scheduleRefresh()
      }
    }
  }

  private func scheduleRefresh() {
    queue.async { [weak self] in
      guard let self else {
        return
      }
      self.pendingRefresh?.cancel()
      let work = DispatchWorkItem { [weak self] in
        self?.refresh()
      }
      self.pendingRefresh = work
      self.queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
  }

  private func refresh() {
    guard let runtime else {
      publishUnavailable()
      return
    }

    runtime.getNowPlayingInfo(on: queue) { [weak self] information in
      guard let self else {
        return
      }
      guard let information, information.count > 0 else {
        self.publishUnavailable()
        return
      }
      runtime.getIsPlaying(on: self.queue) { [weak self] isPlaying in
        guard let self else {
          return
        }
        runtime.getApplicationPID(on: self.queue) { [weak self] pid in
          self?.publish(
            information: information,
            isPlaying: isPlaying,
            processIdentifier: pid,
            runtime: runtime
          )
        }
      }
    }
  }

  private func publish(
    information: NSDictionary,
    isPlaying: Bool,
    processIdentifier: Int32,
    runtime: MediaRemoteRuntime
  ) {
    let application =
      processIdentifier > 0
      ? NSRunningApplication(
        processIdentifier: pid_t(processIdentifier)
      ) : nil
    let bundleIdentifier = application?.bundleIdentifier
    let uniqueIdentifier =
      information[
        "kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
      ] as? String
    let sessionID =
      bundleIdentifier.map {
        "\($0):\(processIdentifier)"
      } ?? uniqueIdentifier.map { "media:\($0)" }
      ?? "media:global"
    let contentIdentity = ContentIdentity(
      sessionID: sessionID,
      uniqueIdentifier: uniqueIdentifier,
      title:
        information["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
      artist:
        information["kMRMediaRemoteNowPlayingInfoArtist"] as? String,
      album:
        information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
    )
    if currentContentIdentity != contentIdentity {
      contentRevision &+= 1
      currentContentIdentity = contentIdentity
    }
    currentSessionID = sessionID

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
      "capabilityRevision": NSNumber(value: 1),
      "contentRevision": NSNumber(value: contentRevision),
      "capabilities": runtime.capabilities.map(\.rawValue).sorted(),
    ]
    copy(
      "kMRMediaRemoteNowPlayingInfoTitle",
      from: information,
      to: "title",
      in: &propertyList
    )
    copy(
      "kMRMediaRemoteNowPlayingInfoArtist",
      from: information,
      to: "artist",
      in: &propertyList
    )
    copy(
      "kMRMediaRemoteNowPlayingInfoAlbum",
      from: information,
      to: "album",
      in: &propertyList
    )
    copy(
      "kMRMediaRemoteNowPlayingInfoDuration",
      from: information,
      to: "duration",
      in: &propertyList
    )
    copy(
      "kMRMediaRemoteNowPlayingInfoElapsedTime",
      from: information,
      to: "progress",
      in: &propertyList
    )
    copy(
      "kMRMediaRemoteNowPlayingInfoArtworkMIMEType",
      from: information,
      to: "artworkMIMEType",
      in: &propertyList
    )
    if let artwork =
      information[
        "kMRMediaRemoteNowPlayingInfoArtworkData"
      ] as? Data,
      artwork.count <= MediaSession.maximumArtworkBytes
    {
      propertyList["artworkData"] = artwork
    }
    if let bundleIdentifier {
      propertyList["sourceBundleIdentifier"] = bundleIdentifier
    }
    if let name = application?.localizedName {
      propertyList["applicationName"] = name
    }
    client?.mediaRemoteDidUpdate(propertyList as NSDictionary)
  }

  private func publishUnavailable() {
    currentSessionID = nil
    currentContentIdentity = nil
    client?.mediaRemoteDidUpdate([
      "protocolVersion": NSNumber(
        value: MediaCompatibilityReport.protocolVersion
      ),
      "isPresent": false,
      "contentRevision": NSNumber(value: contentRevision),
    ])
  }

  private func copy(
    _ sourceKey: String,
    from source: NSDictionary,
    to destinationKey: String,
    in destination: inout [String: Any]
  ) {
    guard let value = source[sourceKey], !(value is NSNull) else {
      return
    }
    destination[destinationKey] = value
  }

  private func stopMonitoringOnQueue() {
    pendingRefresh?.cancel()
    pendingRefresh = nil
    observerTokens.forEach(NotificationCenter.default.removeObserver)
    observerTokens = []
    runtime?.unregisterNotifications()
    runtime = nil
    currentSessionID = nil
    currentContentIdentity = nil
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

  let capabilities: Set<MediaCapability>

  private let handle: UnsafeMutableRawPointer
  private let sendCommandFunction: SendCommandFunction
  private let registerFunction: RegisterFunction
  private let unregisterFunction: UnregisterFunction
  private let informationFunction: InformationFunction
  private let playingFunction: PlayingFunction
  private let pidFunction: PIDFunction
  private let setElapsedTimeFunction: SetElapsedTimeFunction?

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

    var capabilities: Set<MediaCapability> = [
      .playPause,
      .previous,
      .next,
    ]
    if elapsed != nil {
      capabilities.insert(.seek)
    }
    if dlsym(handle, "MRMediaRemoteSetShuffleMode") != nil {
      capabilities.insert(.shuffle)
    }
    if dlsym(handle, "MRMediaRemoteSetRepeatMode") != nil {
      capabilities.insert(.repeatMode)
    }
    self.capabilities = capabilities
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

  func send(action: String, value: NSNumber?) -> Bool {
    switch action {
    case "togglePlayPause":
      return sendCommandFunction(2, nil) != 0
    case "next":
      return sendCommandFunction(4, nil) != 0
    case "previous":
      return sendCommandFunction(5, nil) != 0
    case "shuffle":
      return sendCommandFunction(6, nil) != 0
    case "repeatMode":
      return sendCommandFunction(7, nil) != 0
    case "seek":
      guard let value, let setElapsedTimeFunction,
        value.doubleValue.isFinite, value.doubleValue >= 0
      else {
        return false
      }
      setElapsedTimeFunction(value.doubleValue)
      return true
    default:
      return false
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
