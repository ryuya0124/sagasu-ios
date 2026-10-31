import UIKit
import WebKit

@MainActor
final class AutomaticGoogleLogin {
  enum State { case running, needsInteraction, stopped }
  private let webView: WKWebView
  private let vault: GoogleCredentialVault
  private let onState: (State) -> Void
  private var credential: GoogleCredentialVault.Credential?
  private var submitted: Set<String> = []
  private var timeout: Task<Void, Never>?
  private var passwordURL: URL?
  private var busy = false
  private var generation = UUID()
  var isRunning: Bool { credential != nil }

  init(webView: WKWebView, vault: GoogleCredentialVault, onState: @escaping (State) -> Void) {
    self.webView = webView
    self.vault = vault
    self.onState = onState
  }

  func begin(email: String) -> Bool {
    guard !isRunning, UIApplication.shared.applicationState == .active,
      NSClassFromString("XCTestCase") == nil,
      let saved = try? vault.takeForAttempt(email: email)
    else { return false }
    credential = saved
    submitted = []
    generation = UUID()
    onState(.running)
    timeout = Task { [weak self] in
      try? await Task.sleep(for: .seconds(45))
      guard !Task.isCancelled else { return }
      self?.finish(needsInteraction: true)
    }
    webView.load(URLRequest(url: URL(string: "https://www.google.com/android/find/about?hl=ja")!))
    return true
  }

  func pageChanged() {
    guard let credential, !busy, let url = webView.url, url.scheme == "https", url.user == nil,
      url.password == nil,
      url.port == nil || url.port == 443
    else { return }
    let ticket = generation
    busy = true
    if url.host == "www.google.com", url.path == "/android/find/about" {
      // Follow the actual official sign-in link. No copied OAuth client ID or UA impersonation.
      webView.callAsyncJavaScript(
        """
        const links = [...document.querySelectorAll('a[href]')].filter(a => {
          try { const u = new URL(a.href); return u.protocol === 'https:' &&
            u.hostname === 'accounts.google.com' && u.pathname === '/ServiceLogin'; } catch { return false; }
        });
        if (!links.length) return false;
        links[0].click(); return true;
        """, arguments: [:], in: nil, in: .page
      ) { [weak self] result in
        guard let self, self.generation == ticket else { return }
        self.busy = false
        if case .failure = result { self.finish(needsInteraction: true) }
      }
      return
    }
    guard url.host == "accounts.google.com" else {
      busy = false
      return
    }
    // WebKit arguments keep credentials out of JavaScript source, logs and message payloads.
    webView.callAsyncJavaScript(
      "return window.AndroidFindLogin ? window.AndroidFindLogin.step(email, password, submitted) : 'manual';",
      arguments: [
        "email": credential.email, "password": passwordURL == url ? credential.password : "",
        "submitted": Array(submitted),
      ],
      in: nil, in: .page
    ) { [weak self] result in
      guard let self, self.generation == ticket else { return }
      self.busy = false
      guard case .success(let value) = result, let stage = value as? String else {
        self.finish(needsInteraction: true)
        return
      }
      switch stage {
      case "passwordRejected":
        try? self.vault.remove(email: credential.email)
        self.finish(needsInteraction: true)
      case "passwordNeeded":
        self.passwordURL = url
        self.pageChanged()
      case "identifier", "account", "password", "alternative", "passwordMethod":
        self.submitted.insert(stage)
      case "waiting": break
      default: self.finish(needsInteraction: true)
      }
    }
  }

  func finish(needsInteraction: Bool = false) {
    let wasRunning = isRunning
    generation = UUID()
    timeout?.cancel()
    timeout = nil
    credential = nil
    passwordURL = nil
    submitted = []
    busy = false
    if wasRunning { onState(needsInteraction ? .needsInteraction : .stopped) }
  }
}
