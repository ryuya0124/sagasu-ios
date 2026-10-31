import Foundation
@preconcurrency import GoogleSignIn
import UIKit

@MainActor
protocol GoogleAccountProviding {
  func signIn(presenting: UIViewController) async throws -> GoogleAccountProfile
  func restore() async throws -> GoogleAccountProfile?
  func signOut()
  func handleCallback(_ url: URL) -> Bool
}

/// Use Google's supported system-browser flow for account selection and passkeys.
/// Neither the SDK's tokens nor Safari cookies are injected into Find Hub's WebView.
@MainActor
final class GoogleSDKAccountProvider: GoogleAccountProviding {
  private let configuration: GoogleSignInConfiguration?

  init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
    configuration = GoogleSignInConfiguration(info: info)
  }

  func signIn(presenting controller: UIViewController) async throws -> GoogleAccountProfile {
    try configure()
    do {
      let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller)
      return try profile(from: result.user)
    } catch let error as GoogleAccountSignInError {
      throw error
    } catch {
      let failure = error as NSError
      if failure.domain == kGIDSignInErrorDomain,
        failure.code == GIDSignInError.canceled.rawValue
      {
        throw GoogleAccountSignInError.cancelled
      }
      // SDK error descriptions can contain OAuth URLs. Keep them out of app notices and logs.
      throw GoogleAccountSignInError.unavailable
    }
  }

  func restore() async throws -> GoogleAccountProfile? {
    guard configuration != nil else { return nil }
    try configure()
    guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return nil }
    let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
    return try profile(from: user)
  }

  func signOut() {
    GIDSignIn.sharedInstance.signOut()
  }

  func handleCallback(_ url: URL) -> Bool {
    guard configuration?.acceptsCallback(url) == true else { return false }
    // The SDK validates the OAuth response and the state of the pending request.
    return GIDSignIn.sharedInstance.handle(url)
  }

  private func configure() throws {
    guard let configuration else { throw GoogleAccountSignInError.notConfigured }
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: configuration.clientID)
  }

  private func profile(from user: GIDGoogleUser) throws -> GoogleAccountProfile {
    guard let email = user.profile?.email,
      let profile = GoogleAccountProfile(email: email, name: user.profile?.name)
    else { throw GoogleAccountSignInError.missingProfile }
    return profile
  }
}
