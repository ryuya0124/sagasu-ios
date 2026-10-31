import Foundation
import Observation
import UIKit

/// Google identity and the Find Hub connection have independent success states.
@MainActor
@Observable
final class GoogleAccountSignIn {
  private(set) var account: GoogleAccountProfile?
  private(set) var isWorking = false
  @ObservationIgnored private let provider: any GoogleAccountProviding
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var didAttemptRestore = false

  init(provider: any GoogleAccountProviding = GoogleSDKAccountProvider()) {
    self.provider = provider
  }

  func signIn(presenting controller: UIViewController) async throws -> GoogleAccountProfile? {
    guard !isWorking else { return nil }
    isWorking = true
    didAttemptRestore = true
    let token = generation
    defer { isWorking = false }

    do {
      let selected = try await provider.signIn(presenting: controller)
      guard generation == token else {
        // A sign-out during the request must also remove credentials saved by a late SDK result.
        provider.signOut()
        return nil
      }
      account = selected
      return selected
    } catch GoogleAccountSignInError.cancelled {
      return nil
    } catch {
      guard generation == token else { return nil }
      throw error
    }
  }

  func restoreIfNeeded() async {
    guard !didAttemptRestore, !isWorking else { return }
    didAttemptRestore = true
    isWorking = true
    let token = generation
    defer { isWorking = false }

    do {
      let restored = try await provider.restore()
      guard generation == token else {
        provider.signOut()
        return
      }
      account = restored
    } catch {
      // A failed silent restore leaves sign-in available; it never opens a login prompt.
    }
  }

  func signOut() {
    generation = UUID()
    account = nil
    provider.signOut()
    // Keep an in-flight request busy until it finishes, preventing overlapping SDK sessions.
  }

  func handleCallback(_ url: URL) -> Bool {
    provider.handleCallback(url)
  }
}
