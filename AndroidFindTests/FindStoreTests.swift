import CoreLocation
import Observation
import WebKit
import XCTest

@testable import AndroidFind

@MainActor
@Observable
private final class SessionStub: FindSession {
  var devices: [FindDevice] = []
  var isConnected = true
  var status = "接続済み"
  var isLoading = false
  var isRefreshing = false
  var requiresSignIn = false
  var connectionError: String?
  var canGoBack = false
  var onEvent: (([String: Any]) -> Void)?
  var webView: WKWebView { fatalError("Unit tests do not display a browser") }
  var selections: [String] = []
  var rings: [String] = []
  var stops: [String] = []
  var deviceActions: [(DeviceAction, String)] = []
  var actionCancellations = 0
  var cancellations = 0
  var reloads = 0
  var preparedAccounts: [String] = []
  func prepareSignIn(accountEmail: String) { preparedAccounts.append(accountEmail) }
  func start() {}
  func loadHome() { reloads += 1 }
  func goBack() {}
  func refreshDevices() {}
  func select(_ id: String) { selections.append(id) }
  func cancelSelection() { cancellations += 1 }
  func refresh(_ id: String) { selections.append(id) }
  func playSound(_ id: String) { rings.append(id) }
  func stopSound(_ id: String) { stops.append(id) }
  func openDeviceAction(_ action: DeviceAction, for id: String) {
    deviceActions.append((action, id))
  }
  func cancelDeviceAction() { actionCancellations += 1 }
  func signOutLocally() async {
    devices = []
    isConnected = false
  }
  func emit(_ payload: [String: Any]) { onEvent?(payload) }
}

@MainActor
private struct PlaceStub: PlaceResolving {
  func name(for coordinate: CLLocationCoordinate2D) async -> String? { nil }
}

final class FindStoreTests: XCTestCase {
  @MainActor
  func testNativeGoogleSelectionDoesNotAuthorizeFindHubAndRejectsAnotherAccountsData() async throws
  {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(service: "test-google-selection-\(UUID())"),
      arguments: [])
    session.emit(["type": "account", "email": "first@example.com"])
    session.emit(inventory)
    await store.connect(usingGoogleAccount: "second@example.com")
    XCTAssertNil(store.accountEmail)
    XCTAssertEqual(store.preferredAccountEmail, "second@example.com")
    XCTAssertFalse(session.isConnected)
    XCTAssertTrue(store.devices.isEmpty)
    XCTAssertTrue(store.showGoogle)
    XCTAssertEqual(session.preparedAccounts, ["second@example.com"])

    session.emit(["type": "account", "email": "first@example.com"])
    var wrong = inventory
    wrong["accountEmail"] = "first@example.com"
    session.emit(wrong)
    XCTAssertNil(store.accountEmail)
    XCTAssertTrue(store.devices.isEmpty)

    session.emit(["type": "account", "email": "second@example.com"])
    var correct = inventory
    correct["accountEmail"] = "second@example.com"
    session.emit(correct)
    XCTAssertEqual(store.accountEmail, "second@example.com")
    XCTAssertFalse(store.devices.isEmpty)
    XCTAssertTrue(session.isConnected)
  }

  @MainActor
  func testSelectingTheSameGoogleAccountKeepsTheConfirmedFindHubSession() async throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(service: "test-google-same-account-\(UUID())"),
      arguments: [])
    session.emit(["type": "account", "email": "person@example.com"])
    session.emit(inventory)
    let previousDevices = store.devices
    await store.connect(usingGoogleAccount: "person@example.com")
    XCTAssertTrue(session.isConnected)
    XCTAssertEqual(store.devices, previousDevices)
    XCTAssertFalse(store.showGoogle)
  }

  @MainActor
  func testInventoryLoadsLocationsInTheListWithoutSelectingADevice() throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(service: "test-prefetch-\(UUID())"), arguments: [])
    session.emit(inventory)
    XCTAssertNil(store.selectedID)
    XCTAssertFalse(store.isLocating)
    XCTAssertEqual(store.prefetchingID, "one")
    XCTAssertEqual(store.locationLookupStatus(for: "two"), "位置情報の取得待ち")
    XCTAssertEqual(session.selections, ["one"])
    session.emit(location("one"))
    XCTAssertEqual(store.devices[0].coordinate?.latitude, 35)
    XCTAssertNil(store.selectedID)
    XCTAssertEqual(store.prefetchingID, "two")
    XCTAssertEqual(session.selections, ["one", "two"])
    session.emit(["type": "status", "id": "two", "connectionStatus": "デバイスにアクセスできません"])
    XCTAssertNil(store.prefetchingID)
    XCTAssertNil(cache.load()?.selectedID)
    XCTAssertEqual(store.locationLookupStatus(for: "two"), "デバイスにアクセスできません")
  }

  @MainActor
  func testManualSelectionPromotesOrPreemptsPrefetchAndIgnoresLateErrors() {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(service: "test-prefetch-\(UUID())"), arguments: [])
    session.emit(inventory)
    store.select(store.devices[0])
    XCTAssertEqual(session.selections, ["one"])
    XCTAssertNil(store.prefetchingID)
    XCTAssertEqual(store.selectedID, "one")
    store.select(store.devices[1])
    session.emit(["type": "error", "operation": "location", "id": "one", "message": "late"])
    XCTAssertEqual(store.selectedID, "two")
    XCTAssertTrue(store.isLocating)
    XCTAssertNil(store.locationError)
    session.emit(location("two"))
    XCTAssertFalse(store.isLocating)
  }

  @MainActor
  func testUnresponsivePrefetchMovesOnWithoutOpeningAnErrorAlert() async throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(service: "test-prefetch-\(UUID())"),
      prefetchTimeout: .milliseconds(10), arguments: [])
    session.emit(inventory)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(session.selections, ["one", "two"])
    XCTAssertNil(store.prefetchingID)
    XCTAssertNil(store.selectedID)
    XCTAssertNil(store.notice)
    XCTAssertNil(store.locationError)
  }

  @MainActor
  func testPrefetchStopsForTheGoogleScreenAndRestartsWhenTheListReturns() {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(service: "test-prefetch-\(UUID())"), arguments: [])
    session.emit(inventory)
    store.connect()
    XCTAssertNil(store.prefetchingID)
    XCTAssertTrue(store.showGoogle)
    store.showGoogle = false
    store.googleBrowserPresented(false)
    XCTAssertEqual(store.prefetchingID, "one")
    store.pauseLocationPrefetch()
    XCTAssertNil(store.prefetchingID)
    store.resume()
    XCTAssertEqual(store.prefetchingID, "one")
  }

  @MainActor
  func testConsentForAPreviousAccountCannotSaveOrRemoveAnotherAccountsPassword() throws {
    let cache = cache()
    defer { cache.clear() }
    let vault = GoogleCredentialVault(
      service: "dev.ryuya.AndroidFind.credentials-tests.\(UUID().uuidString)")
    defer { try? vault.removeAll() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(), credentialVault: vault,
      arguments: [])
    session.emit(["type": "account", "email": "first@example.com"])
    session.emit(["type": "account", "email": "second@example.com"])
    XCTAssertThrowsError(
      try store.saveAutomaticLogin(
        password: "synthetic", consent: true, expectedEmail: "first@example.com"))
    XCTAssertNil(try vault.load(email: "second@example.com"))
    try store.saveAutomaticLogin(
      password: "second-synthetic", consent: true, expectedEmail: "second@example.com")
    XCTAssertThrowsError(try store.removeAutomaticLogin(expectedEmail: "first@example.com"))
    XCTAssertNotNil(try vault.load(email: "second@example.com"))
  }

  @MainActor
  func testCredentialConsentAndLogoutRemoveSavedAutomaticLogin() async throws {
    let cache = cache()
    defer { cache.clear() }
    let vault = GoogleCredentialVault(
      service: "dev.ryuya.AndroidFind.credentials-tests.\(UUID().uuidString)")
    defer { try? vault.removeAll() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(), credentialVault: vault,
      arguments: [])
    session.emit(["type": "account", "email": "person@example.com"])
    XCTAssertFalse(store.automaticLoginEnabled)
    XCTAssertThrowsError(
      try store.saveAutomaticLogin(
        password: "synthetic", consent: false, expectedEmail: "person@example.com"))
    XCTAssertFalse(store.automaticLoginEnabled)
    try store.saveAutomaticLogin(
      password: "synthetic", consent: true, expectedEmail: "person@example.com")
    XCTAssertTrue(store.automaticLoginEnabled)
    try store.removeAutomaticLogin(expectedEmail: "person@example.com")
    XCTAssertFalse(store.automaticLoginEnabled)
    XCTAssertNil(try vault.load(email: "person@example.com"))
    try store.saveAutomaticLogin(
      password: "synthetic", consent: true, expectedEmail: "person@example.com")
    session.emit(["type": "account", "email": "another@example.com"])
    XCTAssertNil(try vault.load(email: "person@example.com"))
    XCTAssertFalse(store.automaticLoginEnabled)
    session.emit(["type": "account", "email": "person@example.com"])
    try store.saveAutomaticLogin(
      password: "synthetic", consent: true, expectedEmail: "person@example.com")
    await store.disconnect()
    XCTAssertFalse(store.automaticLoginEnabled)
    XCTAssertNil(try vault.load(email: "person@example.com"))
  }

  @MainActor
  func testSecurityActionsOpenOnlyForTheConfirmedDeviceAndKeepTheGoogleSheetVisible() throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(["type": "account", "email": "owner@example.com"])
    session.emit(inventory)
    store.select(store.devices[0])
    XCTAssertNil(store.selectedDevice?.coordinate)
    let request = try XCTUnwrap(store.actionRequest(.erase))
    XCTAssertTrue(session.deviceActions.isEmpty)  // Showing native confirmation sends nothing.
    store.openDeviceAction(request)
    XCTAssertEqual(session.deviceActions.count, 1)
    XCTAssertEqual(session.deviceActions.first?.0, .erase)
    XCTAssertEqual(session.deviceActions.first?.1, "one")
    session.emit(inventory)
    XCTAssertTrue(store.showGoogle)
    session.emit(["type": "deviceActionOpened", "id": "one", "action": "erase"])
    XCTAssertTrue(store.showGoogle)
    XCTAssertNotNil(store.googleAction)
    XCTAssertNil(store.notice)  // Opening or closing the flow is not execution success.
    store.googleDidDismiss()
    XCTAssertNil(store.googleAction)
    XCTAssertGreaterThan(session.actionCancellations, 0)
  }

  @MainActor
  func testStaleSecurityConfirmationCannotTargetAnotherDeviceOrAccount() throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(["type": "account", "email": "first@example.com"])
    session.emit(inventory)
    store.select(store.devices[0])
    let request = try XCTUnwrap(store.actionRequest(.lock))
    store.closeDevice()
    store.openDeviceAction(request)
    XCTAssertTrue(session.deviceActions.isEmpty)
    session.emit(["type": "account", "email": "second@example.com"])
    session.emit(inventory)
    store.select(store.devices[0])
    store.openDeviceAction(request)
    XCTAssertTrue(session.deviceActions.isEmpty)
  }

  @MainActor
  func testDemoAndExpiredLoginCannotQueueSecurityActions() throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    store.enableDemo()
    store.select(store.devices[0])
    XCTAssertNil(store.actionRequest(.markFound))
    store.leaveDemo()
    session.emit(inventory)
    store.select(store.devices[0])
    let request = try XCTUnwrap(store.actionRequest(.markFound))
    session.emit(["type": "auth"])
    store.openDeviceAction(request)
    XCTAssertTrue(store.showGoogle)
    XCTAssertNil(store.googleAction)
    XCTAssertTrue(session.deviceActions.isEmpty)
  }

  @MainActor
  func testAccountChangeClearsOldDataAndRejectsLateEventsFromThePreviousAccount() throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(["type": "account", "email": "first@example.com"])
    var firstInventory = inventory
    firstInventory["accountEmail"] = "first@example.com"
    session.emit(firstInventory)
    store.select(store.devices[0])
    var firstPosition = location("one")
    firstPosition["accountEmail"] = "first@example.com"
    session.emit(firstPosition)
    session.emit(["type": "account", "email": "second@example.com"])
    XCTAssertTrue(store.devices.isEmpty)
    XCTAssertNil(store.selectedID)
    XCTAssertEqual(store.accountEmail, "second@example.com")
    var secondInventory = inventory
    secondInventory["accountEmail"] = "second@example.com"
    session.emit(secondInventory)
    session.emit(firstPosition)
    XCTAssertNil(store.devices[0].coordinate)
    XCTAssertEqual(cache.load()?.accountEmail, "second@example.com")
    var secondPosition = location("one")
    secondPosition["accountEmail"] = "second@example.com"
    session.emit(secondPosition)
    XCTAssertEqual(store.devices[0].coordinate?.latitude, 35)
  }

  @MainActor
  func testSwitchAccountRemovesSavedSessionDataBeforePresentingTheNextLogin() async throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(["type": "account", "email": "first@example.com"])
    await store.switchGoogleAccount()
    XCTAssertNil(store.accountEmail)
    XCTAssertNil(cache.load())
    XCTAssertTrue(store.devices.isEmpty)
    XCTAssertTrue(store.showGoogle)
    XCTAssertFalse(session.isConnected)
  }

  @MainActor
  func testProviderUnavailableKeepsLastLocationMarkedOldAndDisablesSound() {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(inventory)
    store.select(store.devices[0])
    session.emit(location("one"))
    XCTAssertTrue(store.canOperateDevice)
    session.emit(["type": "status", "id": "one", "connectionStatus": "デバイスにアクセスできません"])
    XCTAssertFalse(store.isLocating)
    XCTAssertFalse(store.canOperateDevice)
    XCTAssertEqual(store.selectedDevice?.coordinate?.latitude, 35)
    XCTAssertEqual(store.selectedDevice?.isCached, true)
    XCTAssertEqual(store.selectedDevice?.connectionStatus, "デバイスにアクセスできません")
    session.emit(location("one"))
    XCTAssertTrue(store.canOperateDevice)
    XCTAssertNil(store.selectedDevice?.connectionStatus)
    XCTAssertEqual(store.selectedDevice?.isCached, false)
  }

  @MainActor
  func testExpiredAuthenticationPreservesProtectedLastKnownData() throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(inventory)
    store.select(store.devices[0])
    session.emit(location("one"))
    session.emit(["type": "auth"])
    XCTAssertEqual(store.selectedID, "one")
    XCTAssertEqual(store.selectedDevice?.coordinate?.latitude, 35)
    XCTAssertEqual(store.selectedDevice?.isCached, true)
    XCTAssertFalse(store.canOperateDevice)
    XCTAssertFalse(store.isLocating)
    XCTAssertEqual(cache.load()?.selectedID, "one")
    session.emit(inventory)
    XCTAssertTrue(store.isLocating)
  }

  @MainActor
  func testOfflineStatusDoesNotInventOrRefreshAPosition() throws {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(inventory)
    store.select(store.devices[0])
    session.emit([
      "type": "status", "id": "one", "battery": 60, "isCharging": false, "network": "Test Wi-Fi",
    ])
    XCTAssertEqual(store.selectedDevice?.battery, 60)
    XCTAssertEqual(store.selectedDevice?.isCharging, false)
    XCTAssertNotNil(store.selectedDevice?.statusReceivedAt)
    XCTAssertNil(store.selectedDevice?.coordinate)
    XCTAssertNil(store.selectedDevice?.locationReceivedAt)
    XCTAssertTrue(store.isLocating)
    XCTAssertEqual(cache.load()?.devices.first?.network, "Test Wi-Fi")
  }

  private func cache() -> DeviceCache {
    DeviceCache(
      fileURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        .appending(
          path: "devices.json"))
  }

  private var inventory: [String: Any] {
    [
      "type": "devices",
      "devices": [["id": "one", "name": "Phone One"], ["id": "two", "name": "Phone Two"]],
    ]
  }

  private func location(_ id: String) -> [String: Any] {
    [
      "type": "location", "id": id, "latitude": 35.0, "longitude": 139.0, "battery": 60,
      "lastSeen": "たった今",
    ]
  }

  @MainActor
  func testRestoresCachedSelectionAndRefreshesItWhenInventoryArrives() throws {
    let cache = cache()
    defer { cache.clear() }
    let old = FindDevice(
      id: "one", name: "Old Name", latitude: 35, longitude: 139,
      locationReceivedAt: .now.addingTimeInterval(-3600))
    try cache.save(devices: [old], selectedID: "one")
    let session = SessionStub()
    session.isConnected = false
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    XCTAssertEqual(store.selectedDevice?.coordinate?.latitude, 35)
    XCTAssertEqual(store.selectedDevice?.isCached, true)
    XCTAssertTrue(session.selections.isEmpty)
    session.emit(inventory)
    XCTAssertEqual(store.selectedDevice?.name, "Phone One")
    XCTAssertEqual(store.selectedDevice?.coordinate?.latitude, 35)
    XCTAssertEqual(session.selections, ["one"])
    XCTAssertTrue(store.isLocating)
    session.emit(location("one"))
    XCTAssertFalse(store.isLocating)
    XCTAssertEqual(store.selectedDevice?.isCached, false)
  }

  @MainActor
  func testSwitchingAndClosingIgnoresLateErrorsFromPreviousDevice() {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(inventory)
    store.select(store.devices[0])
    store.select(store.devices[1])
    session.emit(["type": "error", "operation": "location", "id": "one", "message": "old timeout"])
    XCTAssertTrue(store.isLocating)
    XCTAssertNil(store.locationError)
    XCTAssertNil(store.notice)
    store.closeDevice()
    session.emit(location("one"))
    XCTAssertNil(store.selectedID)
    XCTAssertFalse(store.isLocating)
    XCTAssertGreaterThanOrEqual(session.cancellations, 3)
    XCTAssertNil(cache.load()?.selectedID)
  }

  @MainActor
  func testPlayingSoundSurvivesDeviceSwitchAndFailedStop() {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(inventory)
    store.select(store.devices[0])
    session.emit(location("one"))
    store.playSound()
    XCTAssertEqual(session.rings, ["one"])
    session.emit(["type": "sound", "id": "one", "playing": true])
    store.select(store.devices[1])
    XCTAssertEqual(store.soundState, .idle)
    store.select(store.devices[0])
    XCTAssertTrue(store.canOperateDevice)
    session.emit(location("one"))
    XCTAssertEqual(store.soundState, .playing)
    store.playSound()
    XCTAssertEqual(session.stops, ["one"])
    session.emit(["type": "error", "operation": "sound", "id": "one", "message": "stop failed"])
    XCTAssertEqual(store.soundState, .playing)
  }

  @MainActor
  func testDemoDoesNotOperateRealDevicesOrReplaceTheirCache() throws {
    let cache = cache()
    defer { cache.clear() }
    try cache.save(devices: [FindDevice(id: "one", name: "Real Phone")], selectedID: nil)
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    store.enableDemo()
    store.select(store.devices[0])
    store.playSound()
    XCTAssertTrue(session.rings.isEmpty)
    XCTAssertEqual(cache.load()?.devices.map(\.id), ["one"])
    XCTAssertTrue(store.devices.allSatisfy(\.isDemo))
  }

  @MainActor
  func testNetworkFailureKeepsLastKnownPositionForRetry() {
    let cache = cache()
    defer { cache.clear() }
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(inventory)
    store.select(store.devices[0])
    session.emit(location("one"))
    session.isConnected = false
    session.emit(["type": "connectionError", "message": "offline"])
    XCTAssertEqual(store.selectedDevice?.coordinate?.latitude, 35)
    XCTAssertEqual(store.selectedDevice?.isCached, true)
    XCTAssertFalse(store.isLocating)
    store.retryConnection()
    XCTAssertEqual(session.reloads, 1)
  }

  @MainActor
  func testSignOutRemovesLocalDeviceCache() async throws {
    let cache = cache()
    let session = SessionStub()
    let store = FindStore(
      session: session, cache: cache, placeResolver: PlaceStub(),
      credentialVault: GoogleCredentialVault(
        service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)"), arguments: [])
    session.emit(inventory)
    store.select(store.devices[0])
    session.emit(location("one"))
    XCTAssertNotNil(cache.load())
    await store.disconnect()
    XCTAssertNil(cache.load())
    XCTAssertTrue(store.devices.isEmpty)
    XCTAssertFalse(session.isConnected)
    XCTAssertNil(store.selectedID)
  }
}
