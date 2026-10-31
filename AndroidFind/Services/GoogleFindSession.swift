import Foundation
import OSLog
import Observation
import UIKit
import WebKit

/// The official web client owns authentication, Punctual updates and E2EE decryption.
/// We call its browser RPC for the inventory and project its device data into SwiftUI.
/// The app's own session is restored from Keychain into WebKit before navigation.
/// Password fields are never inspected.
@MainActor
@Observable
final class GoogleFindSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler,
  WKHTTPCookieStoreObserver, FindSession
{
  var devices: [FindDevice] = []
  var isConnected = false
  var status = "未接続"
  var isLoading = false
  var onEvent: (([String: Any]) -> Void)?
  private(set) var isRefreshing = false
  private(set) var requiresSignIn = false
  private(set) var connectionError: String?
  private(set) var canGoBack = false
  private(set) var isAutomaticallySigningIn = false
  private(set) var isPasskeyPage = false
  @ObservationIgnored private var internalWebView: WKWebView!
  var webView: WKWebView { internalWebView }
  @ObservationIgnored private var connectionTimeout: Task<Void, Never>?
  @ObservationIgnored private var inventoryTimeout: Task<Void, Never>?
  @ObservationIgnored private var pendingSelection: String?
  @ObservationIgnored private var selectionTimeout: Task<Void, Never>?
  @ObservationIgnored private var hasStarted = false
  @ObservationIgnored private var didRestoreSession = false
  @ObservationIgnored private var sessionGeneration = UUID()
  @ObservationIgnored private var snapshotTask: Task<Void, Never>?
  @ObservationIgnored private let vault = GoogleSessionVault()
  @ObservationIgnored private var savedAuthenticatedSession = false
  @ObservationIgnored private var isRestoringSession = false
  @ObservationIgnored private var entryURL: URL?
  @ObservationIgnored private var activeAccountEmail: String?
  @ObservationIgnored private var preferredAccountEmail: String?
  @ObservationIgnored private let credentialVault = GoogleCredentialVault()
  @ObservationIgnored private var automaticEmail: String?
  @ObservationIgnored private var browserPresented = false
  @ObservationIgnored private var renewal: Task<Void, Never>?
  @ObservationIgnored private var renewalDue: Date?
  @ObservationIgnored private var accountMismatch = false
  @ObservationIgnored private var expiryCheckedURL: URL?
  @ObservationIgnored private lazy var automaticLogin = AutomaticGoogleLogin(
    webView: webView, vault: credentialVault
  ) { [weak self] state in
    guard let self else { return }
    switch state {
    case .running:
      self.isAutomaticallySigningIn = true
      self.isConnected = false
      self.requiresSignIn = false
      self.isLoading = true
      self.status = "自動で再ログイン中…"
      self.onEvent?(["type": "reauthenticating"])
    case .needsInteraction:
      self.isAutomaticallySigningIn = false
      self.isLoading = false
      self.requiresSignIn = true
      self.status = "Googleで本人確認が必要です"
      self.onEvent?(["type": "auth", "needsUserInteraction": true])
    case .stopped:
      self.isAutomaticallySigningIn = false
    }
  }
  private static let dataStoreID = UUID(uuidString: "AD1341DA-E560-44CF-93B1-AF78BC000001")!
  private static let logger = Logger(subsystem: "dev.ryuya.AndroidFind", category: "GoogleSession")

  override init() {
    super.init()
    let controller = WKUserContentController()
    controller.add(WeakScriptHandler(self), name: "findHub")
    controller.add(WeakScriptHandler(self), name: "googleLogin")
    if let url = Bundle.main.url(forResource: "GoogleLoginBridge", withExtension: "js"),
      let script = try? String(contentsOf: url, encoding: .utf8)
    {
      controller.addUserScript(
        WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }
    if let url = Bundle.main.url(forResource: "FindHubBridge", withExtension: "js"),
      let script = try? String(contentsOf: url, encoding: .utf8)
    {
      controller.addUserScript(
        WKUserScript(
          source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
    }
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.dataStoreID)
    configuration.userContentController = controller
    internalWebView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.allowsBackForwardNavigationGestures = true
    configuration.websiteDataStore.httpCookieStore.add(self)
    // No user agent impersonation and no exported browser session credentials.
  }

  func start() {
    guard !hasStarted else { return }
    loadHome()
  }

  func prepareSignIn(accountEmail: String) {
    preferredAccountEmail = GoogleAccountIdentity.normalized(accountEmail)
    if !isConnected { loadHome() }
  }

  func loadHome() {
    hasStarted = true
    status = "Googleに接続中…"
    isLoading = true
    requiresSignIn = false
    connectionError = nil
    connectionTimeout?.cancel()
    connectionTimeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(25))
      guard !Task.isCancelled, let self, self.isLoading else { return }
      self.reportConnectionFailure("接続に時間がかかっています。通信環境を確認して再試行してください。")
    }
    let generation = sessionGeneration
    Task { [weak self] in
      guard let self else { return }
      await self.restoreSession()
      guard self.sessionGeneration == generation else { return }
      let url = self.entryURL ?? GoogleFindSignInURL.home(accountEmail: self.preferredAccountEmail)
      self.webView.load(URLRequest(url: url))
    }
  }

  func goBack() {
    if webView.canGoBack { webView.goBack() }
  }

  func refreshDevices() {
    guard !isRefreshing else { return }
    if webView.url == nil || !isConnected {
      loadHome()
      return
    }
    isRefreshing = true
    inventoryTimeout?.cancel()
    inventoryTimeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(15))
      guard !Task.isCancelled, let self, self.isRefreshing else { return }
      self.isRefreshing = false
      self.onEvent?([
        "type": "error", "operation": "inventory", "message": "一覧を更新できませんでした。もう一度お試しください。",
      ])
    }
    call("refreshDevices")
  }

  func select(_ id: String) { requestLocation(id, refresh: false) }
  func refresh(_ id: String) { requestLocation(id, refresh: true) }

  func cancelSelection() {
    selectionTimeout?.cancel()
    pendingSelection = nil
    if isConnected { call("cancelSelection") }
  }

  private func requestLocation(_ id: String, refresh: Bool) {
    pendingSelection = id
    call(refresh ? "refresh" : "select", id: id)
    selectionTimeout?.cancel()
    selectionTimeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(45))
      guard !Task.isCancelled, let self, self.pendingSelection == id else { return }
      self.pendingSelection = nil
      self.onEvent?([
        "type": "error", "operation": "location", "id": id,
        "message": "端末から応答がありません。電源や通信状態を確認して、もう一度お試しください。",
      ])
    }
  }

  func playSound(_ id: String) { call("ring", id: id) }
  func stopSound(_ id: String) { call("stopRing", id: id) }

  func openDeviceAction(_ action: DeviceAction, for id: String) {
    call("openDeviceAction", id: id, action: action.rawValue)
  }

  func cancelDeviceAction() {
    if isConnected { call("cancelDeviceAction") }
  }

  func configureAutomaticLogin(accountEmail: String?) {
    let email = GoogleAccountIdentity.normalized(accountEmail)
    if automaticEmail != email {
      automaticLogin.finish()
      accountMismatch = false
    }
    automaticEmail = email
    scheduleRenewal()
  }

  func setBrowserPresented(_ presented: Bool) {
    browserPresented = presented
    if presented {
      automaticLogin.finish()
      if accountMismatch {
        accountMismatch = false
        activeAccountEmail = nil
        loadHome()
      }
    }
  }

  func retryAutomaticLogin() {
    guard hasStarted, !browserPresented, !isAutomaticallySigningIn,
      requiresSignIn || renewalDue.map({ $0 <= .now }) == true,
      let email = automaticEmail
    else { return }
    _ = automaticLogin.begin(email: email)
  }

  private func scheduleRenewal() {
    renewal?.cancel()
    guard let email = automaticEmail, (try? credentialVault.load(email: email)) != nil else {
      renewalDue = nil
      return
    }
    if renewalDue == nil { renewalDue = .now.addingTimeInterval(45 * 60) }
    renewal = Task { [weak self] in
      let delay = max(1, self?.renewalDue?.timeIntervalSinceNow ?? 45 * 60)
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      self?.retryAutomaticLogin()
    }
  }

  func signOutLocally() async {
    automaticLogin.finish()
    renewal?.cancel()
    renewalDue = nil
    automaticEmail = nil
    isPasskeyPage = false
    accountMismatch = false
    expiryCheckedURL = nil
    sessionGeneration = UUID()
    hasStarted = false
    snapshotTask?.cancel()
    connectionTimeout?.cancel()
    inventoryTimeout?.cancel()
    isLoading = false
    isRefreshing = false
    requiresSignIn = false
    connectionError = nil
    isConnected = false
    savedAuthenticatedSession = false
    entryURL = nil
    activeAccountEmail = nil
    preferredAccountEmail = nil
    vault.delete()
    selectionTimeout?.cancel()
    pendingSelection = nil
    webView.stopLoading()
    webView.loadHTMLString("", baseURL: nil)
    await webView.configuration.websiteDataStore.removeData(
      ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast
    )
    devices = []
    isConnected = false
    status = "未接続"
    hasStarted = false
    didRestoreSession = false
  }

  private func restoreSession() async {
    guard !didRestoreSession else { return }
    didRestoreSession = true
    isRestoringSession = true
    defer { isRestoringSession = false }
    let cookies: [HTTPCookie]
    do {
      entryURL = try vault.loadEntryURL()
      cookies = try vault.load()
      savedAuthenticatedSession = CookieSnapshot.hasAuthenticationCookies(cookies)
      Self.logger.info(
        "Loaded session cookies: \(cookies.count), entry available: \(self.entryURL != nil)"
      )
    } catch {
      Self.logger.error("Session restore failed: \(String(describing: error), privacy: .public)")
      return
    }
    for cookie in cookies {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
          continuation.resume()
        }
      }
    }
    let restored = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
    Self.logger.info(
      "Restored WebKit cookies: \(restored.count), authenticated: \(restored.contains { $0.name == "SID" })"
    )
  }

  func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    scheduleSessionSnapshot()
  }

  private func scheduleSessionSnapshot() {
    guard hasStarted, !isRestoringSession else { return }
    snapshotTask?.cancel()
    let generation = sessionGeneration
    snapshotTask = Task { [weak self] in
      guard let self else { return }
      let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
        self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
          continuation.resume(returning: $0)
        }
      }
      guard !Task.isCancelled, self.sessionGeneration == generation else {
        return
      }
      let authenticated = CookieSnapshot.hasAuthenticationCookies(cookies)
      Self.logger.info("Observed WebKit cookies: \(cookies.count), authenticated: \(authenticated)")
      guard authenticated || (self.isConnected && !self.savedAuthenticatedSession) else { return }
      guard !cookies.isEmpty else { return }
      do {
        try self.vault.save(cookies)
        self.savedAuthenticatedSession = authenticated
        Self.logger.info(
          "Saved session cookies: \(cookies.count), authenticated: \(cookies.contains { $0.name == "SID" })"
        )
      } catch {
        self.onEvent?(["type": "error", "message": "この端末にログイン状態を保存できませんでした。"])
      }
    }
  }

  private func call(_ command: String, id: String? = nil, action: String? = nil) {
    let value = [
      "command": command, "id": id ?? "", "action": action ?? "",
      "expectedAccount": activeAccountEmail ?? "",
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: value),
      let json = String(data: data, encoding: .utf8)
    else { return }
    webView.evaluateJavaScript(
      "(() => { if (!window.AndroidFindBridge) return false; window.AndroidFindBridge.command(\(json)); return true; })()"
    ) {
      [weak self] result, error in
      guard let self else { return }
      if error != nil || result as? Bool != true {
        if command == "refreshDevices" { self.isRefreshing = false }
        self.onEvent?([
          "type": "error", "id": id ?? "",
          "operation": command == "refreshDevices"
            ? "inventory"
            : (command == "openDeviceAction"
              ? "deviceAction"
              : (command == "ring" || command == "stopRing" ? "sound" : "location")),
          "message": "Googleへの接続を確認して、もう一度お試しください。",
        ])
      }
    }
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    if message.name == "googleLogin" {
      guard hasStarted, message.frameInfo.isMainFrame,
        let current = webView.url, current.scheme == "https", current.host == "accounts.google.com",
        let frame = message.frameInfo.request.url, frame.scheme == "https",
        frame.host == "accounts.google.com",
        let payload = message.body as? [String: Any], payload["type"] as? String == "pageChanged"
      else { return }
      isPasskeyPage = current.path.contains("/challenge/pk")
      automaticLogin.pageChanged()
      return
    }
    guard hasStarted, message.frameInfo.isMainFrame,
      let activeURL = webView.url, activeURL.scheme == "https", activeURL.host == "www.google.com",
      activeURL.path.hasPrefix("/android/find"),
      let url = message.frameInfo.request.url,
      url.scheme == "https", url.host == "www.google.com",
      url.path.hasPrefix("/android/find"),
      let payload = message.body as? [String: Any]
    else { return }
    let type = payload["type"] as? String
    if let preferredAccountEmail {
      let reportedEmail = GoogleAccountIdentity.normalized(
        type == "account" ? payload["email"] : payload["accountEmail"])
      guard reportedEmail == preferredAccountEmail else {
        if type == "account" {
          isConnected = false
          requiresSignIn = true
          status = "選択したGoogleアカウントで接続してください"
          onEvent?(["type": "auth", "needsUserInteraction": true])
        }
        return
      }
    }
    if type == "account" {
      guard let email = GoogleAccountIdentity.normalized(payload["email"]) else { return }
      if isAutomaticallySigningIn, let expected = automaticEmail, email != expected {
        accountMismatch = true
        automaticLogin.finish(needsInteraction: true)
        return
      }
      activeAccountEmail = email
    } else if let activeAccountEmail,
      GoogleAccountIdentity.normalized(payload["accountEmail"]) != activeAccountEmail
    {
      return
    }
    let isLocationResult =
      type == "location"
      || (type == "status" && payload["connectionStatus"] as? String != nil)
    if isLocationResult, payload["id"] as? String == pendingSelection {
      pendingSelection = nil
      selectionTimeout?.cancel()
    }
    if type == "devices" {
      readExpiryIfNeeded()
      automaticLogin.finish()
      isLoading = false
      scheduleRenewal()
      isRefreshing = false
      inventoryTimeout?.cancel()
      requiresSignIn = false
      connectionError = nil
    }
    if type == "error", payload["operation"] as? String == "inventory" {
      if !browserPresented, let email = automaticEmail { _ = automaticLogin.begin(email: email) }
      isRefreshing = false
      inventoryTimeout?.cancel()
    }
    if type == "error", payload["id"] as? String == pendingSelection,
      payload["operation"] as? String == "location"
    {
      pendingSelection = nil
      selectionTimeout?.cancel()
    }
    saveEntryURLIfNeeded(url)
    onEvent?(payload)
    if type == "account", preferredAccountEmail != nil, devices.isEmpty {
      // Inventory may have arrived before the account header. Request it again once
      // the selected identity is confirmed instead of accepting unowned data.
      call("refreshDevices")
    }
    if payload["type"] as? String == "devices" || payload["type"] as? String == "location" {
      scheduleSessionSnapshot()
    }
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    isLoading = true
    connectionError = nil
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    isLoading = false
    connectionTimeout?.cancel()
    canGoBack = webView.canGoBack
    isPasskeyPage =
      webView.url?.host == "accounts.google.com"
      && webView.url?.path.contains("/challenge/pk") == true
    Self.logger.info(
      "Navigation finished at host: \(webView.url?.host ?? "none", privacy: .public)")
    if let url = webView.url { saveEntryURLIfNeeded(url) }
    scheduleSessionSnapshot()
    let isLoginPage =
      webView.url?.host == "accounts.google.com"
      || webView.url?.path.hasPrefix("/android/find/about") == true
    if isLoginPage {
      isRefreshing = false
      if isAutomaticallySigningIn {
        isLoading = true
        automaticLogin.pageChanged()
      } else if !browserPresented, let email = automaticEmail, automaticLogin.begin(email: email) {
        return
      } else {
        requiresSignIn = true
        status = "Googleへのログインが必要です"
        onEvent?(["type": "auth"])
      }
    }
  }

  private func readExpiryIfNeeded() {
    guard let email = automaticEmail, (try? credentialVault.load(email: email)) != nil,
      let url = webView.url, GoogleSessionEntry.restorableURL(url) != nil,
      expiryCheckedURL != url
    else { return }
    expiryCheckedURL = url
    let generation = sessionGeneration
    webView.callAsyncJavaScript(
      """
      if (location.protocol !== 'https:' || location.hostname !== 'www.google.com' ||
          !location.pathname.startsWith('/android/find/')) return null;
      const token = new URLSearchParams(location.search).get('access_token');
      if (!token) return null;
      try {
        const response = await fetch('https://oauth2.googleapis.com/tokeninfo?access_token=' + encodeURIComponent(token));
        if (!response.ok) return null;
        const info = await response.json();
        const seconds = Number(info.expires_in);
        return Number.isFinite(seconds) && seconds > 0 ? seconds : null;
      } catch { return null; }
      """, arguments: [:], in: nil, in: .page
    ) { [weak self] result in
      guard let self, self.sessionGeneration == generation, self.automaticEmail == email,
        case .success(let value) = result, let seconds = value as? Double, seconds.isFinite,
        seconds > 0, seconds < 86_400
      else { return }
      self.renewalDue = .now.addingTimeInterval(max(30, seconds - 300))
      self.scheduleRenewal()
    }
  }

  private func saveEntryURLIfNeeded(_ url: URL) {
    guard hasStarted, let url = GoogleSessionEntry.restorableURL(url), url != entryURL else {
      return
    }
    do {
      try vault.saveEntryURL(url)
      entryURL = url
      renewalDue = nil
      Self.logger.info("Saved authenticated entry URL")
    } catch {
      onEvent?(["type": "error", "message": "この端末にログイン状態を保存できませんでした。"])
    }
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    isLoading = false
    guard (error as NSError).code != NSURLErrorCancelled else { return }
    reportConnectionFailure("接続できませんでした。通信環境を確認して再試行してください。")
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    guard (error as NSError).code != NSURLErrorCancelled else { return }
    reportConnectionFailure("Googleへの接続が途切れました。再接続してください。")
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    reportConnectionFailure("Googleへの接続が中断されました。再接続してください。")
  }

  private func reportConnectionFailure(_ message: String) {
    automaticLogin.finish()
    isLoading = false
    isRefreshing = false
    isConnected = false
    connectionTimeout?.cancel()
    inventoryTimeout?.cancel()
    cancelSelection()
    status = "接続できませんでした"
    connectionError = message
    onEvent?(["type": "connectionError", "message": message])
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
    -> WKNavigationActionPolicy
  {
    guard let url = navigationAction.request.url else { return .cancel }
    if url.scheme == "about" { return .allow }
    guard url.scheme == "https", let host = url.host else { return .cancel }
    let allowed =
      host == "google.com" || host.hasSuffix(".google.com")
      || host == "gstatic.com" || host.hasSuffix(".gstatic.com")
      || host == "googleusercontent.com" || host.hasSuffix(".googleusercontent.com")
    return allowed ? .allow : .cancel
  }
}

@MainActor
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
  weak var target: GoogleFindSession?
  init(_ target: GoogleFindSession) { self.target = target }
  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}
