import Observation
import WebKit

@MainActor
protocol FindSession: AnyObject, Observable {
  var devices: [FindDevice] { get set }
  var isConnected: Bool { get set }
  var status: String { get set }
  var isLoading: Bool { get }
  var isRefreshing: Bool { get }
  var requiresSignIn: Bool { get }
  var connectionError: String? { get }
  var canGoBack: Bool { get }
  var isAutomaticallySigningIn: Bool { get }
  var isPasskeyPage: Bool { get }
  var onEvent: (([String: Any]) -> Void)? { get set }
  var webView: WKWebView { get }
  func start()
  func loadHome()
  func goBack()
  func refreshDevices()
  func select(_ id: String)
  func cancelSelection()
  func refresh(_ id: String)
  func playSound(_ id: String)
  func stopSound(_ id: String)
  func openDeviceAction(_ action: DeviceAction, for id: String)
  func cancelDeviceAction()
  func configureAutomaticLogin(accountEmail: String?)
  func retryAutomaticLogin()
  func setBrowserPresented(_ presented: Bool)
  func prepareSignIn(accountEmail: String)
  func signOutLocally() async
}

// Nonbrowser test sessions do not run credential automation.
extension FindSession {
  var isAutomaticallySigningIn: Bool { false }
  var isPasskeyPage: Bool { false }
  func configureAutomaticLogin(accountEmail: String?) {}
  func retryAutomaticLogin() {}
  func setBrowserPresented(_ presented: Bool) {}
  func prepareSignIn(accountEmail: String) {}
}
