import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class FindStore {
  var devices: [FindDevice] = []
  private(set) var selectedID: String?
  private(set) var accountEmail: String?
  private(set) var preferredAccountEmail: String?
  private(set) var automaticLoginEnabled = false
  @ObservationIgnored private let credentialVault: GoogleCredentialVault
  var isDemo = false
  private(set) var googleAction: DeviceActionRequest?
  var googleActionMessage: String?
  var showGoogle = false
  var showAccount = false
  var isLocating = false
  var notice: String?
  var locationError: String?
  var inventoryError: String?
  let google: any FindSession
  @ObservationIgnored private let cache: DeviceCache
  @ObservationIgnored private let placeResolver: any PlaceResolving
  @ObservationIgnored private var placeTasks: [String: Task<Void, Never>] = [:]
  private var soundStates: [String: SoundState] = [:]
  private var pendingSoundStates: [String: SoundState] = [:]
  private var connectAfterAccountDismisses = false
  @ObservationIgnored private var pendingGoogleAccountEmail: String?
  private var restorePendingSelection = false
  private var lastResume: Date?
  private(set) var prefetchingID: String?
  private var prefetchQueue: [String] = []
  private var prefetchAttempts: [String: Date] = [:]
  @ObservationIgnored private var prefetchTimer: Task<Void, Never>?
  @ObservationIgnored private let prefetchTimeout: Duration
  private var forcePrefetchOnInventory = false
  private var appIsActive = true

  enum SoundState: Equatable {
    case idle, sending, playing
  }

  init(
    session: any FindSession = GoogleFindSession(), cache: DeviceCache = DeviceCache(),
    placeResolver: any PlaceResolving = PlaceResolver(),
    credentialVault: GoogleCredentialVault = GoogleCredentialVault(),
    prefetchTimeout: Duration = .seconds(25),
    arguments: [String] = ProcessInfo.processInfo.arguments
  ) {
    google = session
    self.prefetchTimeout = prefetchTimeout
    self.credentialVault = credentialVault
    self.cache = cache
    self.placeResolver = placeResolver
    if let snapshot = cache.load() {
      devices = snapshot.devices
      selectedID = snapshot.selectedID
      accountEmail = snapshot.accountEmail
      restorePendingSelection = selectedID != nil
    }
    updateAutomaticLoginConfiguration()
    google.onEvent = { [weak self] payload in self?.receive(payload) }
    if arguments.contains("--demo") {
      enableDemo()
      if arguments.contains("--detail") { selectedID = devices.first?.id }
    }
    if arguments.contains("--google") { showGoogle = true }
  }

  var selectedDevice: FindDevice? { devices.first { $0.id == selectedID } }
  var soundState: SoundState { selectedID.map { soundState(for: $0) } ?? .idle }
  var hasCachedLocations: Bool { devices.contains { $0.isCached && $0.coordinate != nil } }
  var canOperateDevice: Bool {
    isDemo
      || (google.isConnected
        && (soundState == .playing
          || (!isLocating && selectedDevice?.coordinate != nil
            && selectedDevice?.connectionStatus == nil)))
  }

  func soundState(for id: String) -> SoundState { soundStates[id] ?? .idle }

  func start() {
    guard !isDemo else { return }
    google.start()
    lastResume = .now
  }

  func resume() {
    appIsActive = true
    guard !isDemo, googleAction == nil else { return }
    google.retryAutomaticLogin()
    startLocationPrefetch()
    guard !google.isAutomaticallySigningIn else { return }
    defer { lastResume = .now }
    guard let lastResume, Date.now.timeIntervalSince(lastResume) > 60 else { return }
    if google.isConnected { refresh() } else if !google.requiresSignIn { retryConnection() }
  }

  func connect() {
    cancelLocationPrefetch()
    googleAction = nil
    googleActionMessage = nil
    if isDemo { leaveDemo() }
    if showAccount {
      connectAfterAccountDismisses = true
      showAccount = false
      return
    }
    showGoogle = true
    google.start()
  }

  /// Google profile sign-in does not authorize Find Hub. Keep the last-known account
  /// separate until the official Web client confirms which account supplied its data.
  func connect(usingGoogleAccount email: String) async {
    guard let email = GoogleAccountIdentity.normalized(email) else { return }
    if accountEmail != email {
      await disconnect()
    }
    if isDemo { leaveDemo() }
    preferredAccountEmail = email
    google.prepareSignIn(accountEmail: email)
    if google.isConnected, accountEmail == email {
      showAccount = false
      return
    }
    connect()
  }

  func selectGoogleAccount(_ email: String) {
    guard let email = GoogleAccountIdentity.normalized(email) else { return }
    pendingGoogleAccountEmail = email
    if showAccount {
      showAccount = false
    } else if showGoogle {
      showGoogle = false
    } else {
      connectSelectedGoogleAccount()
    }
  }

  private func connectSelectedGoogleAccount() {
    guard let email = pendingGoogleAccountEmail else { return }
    pendingGoogleAccountEmail = nil
    Task { await connect(usingGoogleAccount: email) }
  }

  func accountDidDismiss() {
    if pendingGoogleAccountEmail != nil {
      connectAfterAccountDismisses = false
      connectSelectedGoogleAccount()
      return
    }
    guard connectAfterAccountDismisses else { return }
    connectAfterAccountDismisses = false
    connect()
  }

  func retryConnection() {
    inventoryError = nil
    locationError = nil
    restorePendingSelection = selectedID != nil
    if google.requiresSignIn { connect() } else { google.loadHome() }
  }

  func enableDemo() {
    guard !isDemo else { return }
    saveCache()
    cancelLocationPrefetch()
    google.cancelSelection()
    cancelPlaceTasks()
    isDemo = true
    let knownDevices = google.devices + (cache.load()?.devices ?? [])
    devices = FindDevice.previews.map { preview in
      var preview = preview
      preview.imageURL = knownDevices.first(where: { $0.name == preview.name })?.imageURL
      return preview
    }
    selectedID = nil
    isLocating = false
    locationError = nil
    showAccount = false
  }

  func leaveDemo() {
    guard isDemo else { return }
    isDemo = false
    let snapshot = cache.load()
    devices =
      google.isConnected
      ? FindDevice.mergingInventory(google.devices, previous: snapshot?.devices ?? [])
      : snapshot?.devices ?? []
    selectedID = snapshot?.selectedID
    if let device = selectedDevice, google.isConnected {
      select(device)
    } else {
      restorePendingSelection = selectedID != nil
      google.start()
    }
  }

  func select(_ device: FindDevice) {
    let promotePrefetch = prefetchingID == device.id
    cancelLocationPrefetch(cancelSession: !promotePrefetch)
    if !promotePrefetch { google.cancelSelection() }
    selectedID = device.id
    locationError = nil
    isLocating = false
    guard !isDemo else { return }
    saveCache()
    guard google.isConnected else {
      restorePendingSelection = true
      return
    }
    restorePendingSelection = false
    isLocating = true
    if !promotePrefetch { google.select(device.id) }
  }

  func closeDevice() {
    google.cancelSelection()
    selectedID = nil
    restorePendingSelection = false
    isLocating = false
    locationError = nil
    saveCache()
    startLocationPrefetch()
  }

  func refresh() {
    guard !isDemo else { return }
    locationError = nil
    inventoryError = nil
    guard google.isConnected else {
      retryConnection()
      return
    }
    if let selectedID {
      isLocating = true
      google.refresh(selectedID)
    } else {
      forcePrefetchOnInventory = true
      google.refreshDevices()
    }
  }

  func refreshInventory() async {
    guard !isDemo else { return }
    inventoryError = nil
    forcePrefetchOnInventory = true
    google.refreshDevices()
    // Keep the native refresh control visible until the browser result or its bounded timeout.
    while google.isRefreshing && !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(100))
    }
  }

  func playSound() {
    guard let selectedID, soundState != .sending else { return }
    guard !isDemo else {
      notice = "デモの端末です。実際のデバイスから音は鳴りません。"
      return
    }
    guard canOperateDevice else { return }
    let previous = soundState
    pendingSoundStates[selectedID] = previous
    soundStates[selectedID] = .sending
    if previous == .playing { google.stopSound(selectedID) } else { google.playSound(selectedID) }
  }

  func locationLookupStatus(for id: String) -> String? {
    if prefetchingID == id { return "位置情報を取得中…" }
    if prefetchQueue.contains(id) { return "位置情報の取得待ち" }
    if prefetchAttempts[id] != nil, let device = devices.first(where: { $0.id == id }),
      device.coordinate == nil
    {
      return device.connectionStatus ?? "位置情報を取得できませんでした"
    }
    return nil
  }

  func googleBrowserPresented(_ presented: Bool) {
    google.setBrowserPresented(presented)
    if presented { cancelLocationPrefetch() } else { startLocationPrefetch() }
  }

  func pauseLocationPrefetch() {
    appIsActive = false
    cancelLocationPrefetch()
  }

  private func cancelLocationPrefetch(cancelSession: Bool = true) {
    prefetchTimer?.cancel()
    prefetchTimer = nil
    if prefetchingID != nil, cancelSession { google.cancelSelection() }
    prefetchingID = nil
    prefetchQueue = []
  }

  private func startLocationPrefetch(force: Bool = false) {
    guard appIsActive, !isDemo, selectedID == nil, !showGoogle, googleAction == nil,
      google.isConnected, !google.isAutomaticallySigningIn
    else { return }
    let now = Date.now
    let candidates =
      devices.filter { device in
        guard device.id != prefetchingID else { return false }
        if !force {
          if let attempt = prefetchAttempts[device.id], now.timeIntervalSince(attempt) < 60 {
            return false
          }
          if device.coordinate != nil, !device.isCached,
            let received = device.locationReceivedAt, now.timeIntervalSince(received) < 120
          {
            return false
          }
        }
        return true
      }
      .map(\.id)
    let valid = Set(devices.map(\.id))
    prefetchQueue = prefetchQueue.filter { valid.contains($0) }
    for id in candidates where !prefetchQueue.contains(id) { prefetchQueue.append(id) }
    startNextLocationPrefetch()
  }

  private func startNextLocationPrefetch() {
    guard prefetchingID == nil, selectedID == nil, appIsActive, !isDemo,
      !showGoogle, googleAction == nil, google.isConnected, !google.isAutomaticallySigningIn
    else { return }
    while let id = prefetchQueue.first {
      prefetchQueue.removeFirst()
      guard let index = devices.firstIndex(where: { $0.id == id }) else { continue }
      prefetchingID = id
      if devices[index].coordinate != nil { devices[index].isCached = true }
      google.select(id)
      prefetchTimer = Task { [weak self, prefetchTimeout] in
        try? await Task.sleep(for: prefetchTimeout)
        guard !Task.isCancelled, let self, self.prefetchingID == id else { return }
        self.finishLocationPrefetch(id)
      }
      return
    }
  }

  private func finishLocationPrefetch(_ id: String) {
    guard prefetchingID == id else { return }
    prefetchTimer?.cancel()
    prefetchTimer = nil
    prefetchAttempts[id] = .now
    prefetchingID = nil
    google.cancelSelection()
    startNextLocationPrefetch()
  }

  func saveAutomaticLogin(password: String, consent: Bool, expectedEmail: String) throws {
    guard let email = accountEmail, email == expectedEmail else {
      throw GoogleCredentialVault.Failure.invalidInput
    }
    try credentialVault.save(email: email, password: password, consent: consent)
    updateAutomaticLoginConfiguration()
    google.retryAutomaticLogin()
  }

  func removeAutomaticLogin(expectedEmail: String) throws {
    guard let email = accountEmail, email == expectedEmail else {
      throw GoogleCredentialVault.Failure.invalidInput
    }
    try credentialVault.remove(email: email)
    updateAutomaticLoginConfiguration()
  }

  private func updateAutomaticLoginConfiguration() {
    automaticLoginEnabled = accountEmail.flatMap { try? credentialVault.load(email: $0) } != nil
    google.configureAutomaticLogin(accountEmail: automaticLoginEnabled ? accountEmail : nil)
  }

  func actionRequest(_ action: DeviceAction) -> DeviceActionRequest? {
    guard !isDemo, let device = selectedDevice else {
      notice = "デモでは端末の保護・解除・消去を実行できません。"
      return nil
    }
    return DeviceActionRequest(
      action: action, deviceID: device.id, deviceName: device.name, accountEmail: accountEmail)
  }

  func openDeviceAction(_ request: DeviceActionRequest) {
    guard !isDemo, selectedID == request.deviceID, accountEmail == request.accountEmail,
      let device = selectedDevice, device.name == request.deviceName
    else {
      notice = "対象の端末またはアカウントが変わりました。端末を選び直してください。"
      return
    }
    guard google.isConnected, !google.requiresSignIn else {
      notice = "Googleにログインしてから、もう一度操作を選んでください。"
      connect()
      return
    }
    googleAction = request
    googleActionMessage = "対象端末のGoogle確認画面を開いています…"
    showGoogle = true
    google.openDeviceAction(request.action, for: request.deviceID)
  }

  func googleDidDismiss() {
    if pendingGoogleAccountEmail != nil {
      connectSelectedGoogleAccount()
      return
    }
    guard googleAction != nil else { return }
    google.cancelDeviceAction()
    googleAction = nil
    googleActionMessage = nil
    // Re-read the authoritative state; closing a sheet is never success evidence.
    if google.isConnected { google.refreshDevices() }
  }

  func disconnect() async {
    pendingGoogleAccountEmail = nil
    cancelLocationPrefetch()
    prefetchAttempts = [:]
    google.configureAutomaticLogin(accountEmail: nil)
    do { try credentialVault.removeAll() } catch { notice = "保存したログイン情報を削除できませんでした。" }
    automaticLoginEnabled = false
    google.cancelDeviceAction()
    googleAction = nil
    googleActionMessage = nil
    showGoogle = false
    cancelPlaceTasks()
    await google.signOutLocally()
    await DeviceImageRepository.shared.removeAll()
    cache.clear()
    devices = []
    selectedID = nil
    accountEmail = nil
    preferredAccountEmail = nil
    restorePendingSelection = false
    isDemo = false
    isLocating = false
    soundStates = [:]
    pendingSoundStates = [:]
    locationError = nil
    inventoryError = nil
    showAccount = false
  }

  func switchGoogleAccount() async {
    await disconnect()
    connect()
  }

  private func receive(_ payload: [String: Any]) {
    guard let type = payload["type"] as? String else { return }
    if let preferredAccountEmail,
      ["account", "devices", "location", "status", "sound", "deviceActionOpened"].contains(type)
    {
      let email = GoogleAccountIdentity.normalized(
        type == "account" ? payload["email"] : payload["accountEmail"])
      guard email == preferredAccountEmail else { return }
    }
    if type == "account" {
      guard let email = GoogleAccountIdentity.normalized(payload["email"]) else { return }
      if let previous = accountEmail, previous != email {
        cancelLocationPrefetch()
        prefetchAttempts = [:]
        do { try credentialVault.remove(email: previous) } catch {
          notice = "前のアカウントの保存パスワードを削除できませんでした。"
        }
        google.cancelDeviceAction()
        googleAction = nil
        googleActionMessage = nil
        cancelPlaceTasks()
        google.cancelSelection()
        devices = []
        selectedID = nil
        restorePendingSelection = false
        soundStates = [:]
        pendingSoundStates = [:]
        locationError = nil
        inventoryError = nil
        isLocating = false
        cache.clear()
      }
      accountEmail = email
      updateAutomaticLoginConfiguration()
      saveCache()
      return
    }
    // Browser events are account-tagged; the session also sends local errors without a tag.
    if let accountEmail, payload.keys.contains("accountEmail"),
      GoogleAccountIdentity.normalized(payload["accountEmail"]) != accountEmail
    {
      return
    }
    switch type {
    case "devices":
      guard let received = BridgeDecoder.devices(from: payload) else { return }
      google.devices = received
      google.isConnected = true
      google.status = "接続済み"
      inventoryError = nil
      guard !isDemo else { return }
      devices = FindDevice.mergingInventory(received, previous: devices)
      if let selectedID, !devices.contains(where: { $0.id == selectedID }) { closeDevice() }
      if googleAction == nil { showGoogle = false }
      saveCache()
      if let id = prefetchingID, !devices.contains(where: { $0.id == id }) {
        cancelLocationPrefetch()
      }
      if restorePendingSelection, let device = selectedDevice {
        select(device)
      } else {
        startLocationPrefetch(force: forcePrefetchOnInventory)
      }
      forcePrefetchOnInventory = false
    case "status":
      guard !isDemo, let id = payload["id"] as? String,
        let index = devices.firstIndex(where: { $0.id == id })
      else { return }
      BridgeDecoder.applyLocation(payload, to: &devices[index])
      devices[index].statusReceivedAt = .now
      if devices[index].connectionStatus != nil {
        if devices[index].coordinate != nil { devices[index].isCached = true }
        if id == selectedID {
          isLocating = false
          locationError = nil
        }
      }
      saveCache()
      if devices[index].connectionStatus != nil { finishLocationPrefetch(id) }
    case "location":
      guard !isDemo, let id = payload["id"] as? String,
        let index = devices.firstIndex(where: { $0.id == id })
      else { return }
      let oldCoordinate = devices[index].coordinate
      BridgeDecoder.applyLocation(payload, to: &devices[index])
      guard let coordinate = devices[index].coordinate,
        payload["latitude"] as? Double == coordinate.latitude,
        payload["longitude"] as? Double == coordinate.longitude
      else { return }
      devices[index].locationReceivedAt = .now
      devices[index].isCached = false
      if let oldCoordinate,
        CLLocation(latitude: oldCoordinate.latitude, longitude: oldCoordinate.longitude)
          .distance(
            from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) > 50
      {
        devices[index].place = nil
      }
      if id == selectedID {
        isLocating = false
        locationError = nil
      }
      saveCache()
      if devices[index].place == nil { resolvePlace(for: id, coordinate: coordinate) }
      finishLocationPrefetch(id)
    case "sound":
      guard !isDemo, let id = payload["id"] as? String,
        devices.contains(where: { $0.id == id })
      else { return }
      soundStates[id] = payload["playing"] as? Bool == true ? .playing : .idle
      pendingSoundStates[id] = nil
    case "deviceActionOpened":
      guard let request = googleAction,
        payload["id"] as? String == request.deviceID,
        payload["action"] as? String == request.action.rawValue
      else { return }
      googleActionMessage = "端末名と操作内容を確認し、Googleの画面で続けてください。"
    case "reauthenticating":
      cancelLocationPrefetch()
      isLocating = false
      for index in devices.indices { devices[index].isCached = true }
    case "auth":
      cancelLocationPrefetch()
      updateAutomaticLoginConfiguration()
      google.isConnected = false
      google.devices = []
      google.status = "ログインが必要です"
      if payload["needsUserInteraction"] as? Bool == true { connect() }
      cancelPlaceTasks()
      if !isDemo {
        // Expired authentication must not erase the user's last-known device data.
        // Only an explicit local sign-out removes that protected cache.
        isLocating = false
        restorePendingSelection = selectedID != nil
        for index in devices.indices { devices[index].isCached = true }
        saveCache()
        pendingSoundStates = [:]
      }
    case "connectionError":
      cancelLocationPrefetch()
      isLocating = false
      restorePendingSelection = selectedID != nil
      for index in devices.indices where !devices[index].isDemo { devices[index].isCached = true }
      saveCache()
    case "error":
      let message = payload["message"] as? String ?? "Googleに接続できませんでした。"
      let id = payload["id"] as? String
      switch payload["operation"] as? String {
      case "location":
        if let id, prefetchingID == id {
          finishLocationPrefetch(id)
          return
        }
        guard id == nil || id == selectedID else { return }
        isLocating = false
        locationError = message
      case "deviceAction":
        guard let request = googleAction, id == request.deviceID else { return }
        googleActionMessage = message
      case "inventory": inventoryError = message
      case "sound":
        guard let id else { return }
        soundStates[id] = pendingSoundStates.removeValue(forKey: id) ?? .idle
        notice = message
      default:
        isLocating = false
        notice = message
      }
    default: break
    }
  }

  private func resolvePlace(for id: String, coordinate: CLLocationCoordinate2D) {
    placeTasks[id]?.cancel()
    placeTasks[id] = Task { [weak self] in
      guard let self else { return }
      let place = await self.placeResolver.name(for: coordinate)
      guard !Task.isCancelled, !self.isDemo, let place,
        let index = self.devices.firstIndex(where: { $0.id == id }),
        self.devices[index].latitude == coordinate.latitude,
        self.devices[index].longitude == coordinate.longitude
      else { return }
      self.devices[index].place = place
      self.saveCache()
    }
  }

  private func cancelPlaceTasks() {
    for task in placeTasks.values { task.cancel() }
    placeTasks.removeAll()
  }

  private func saveCache() {
    guard !isDemo else { return }
    try? cache.save(devices: devices, selectedID: selectedID, accountEmail: accountEmail)
  }
}
