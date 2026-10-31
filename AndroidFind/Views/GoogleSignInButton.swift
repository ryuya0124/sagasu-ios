import GoogleSignInSwift
import SwiftUI

struct GoogleSignInButton: View {
  let onSignedIn: (GoogleAccountProfile) -> Void
  @Environment(GoogleAccountSignIn.self) private var accounts
  @Environment(\.colorScheme) private var colorScheme
  @State private var errorMessage: String?
  @State private var presenter = AuthenticationPresenter()

  var body: some View {
    GoogleSignInSwift.GoogleSignInButton(
      scheme: colorScheme == .dark ? .dark : .light,
      style: .wide,
      state: accounts.isWorking ? .disabled : .normal,
      action: signIn
    )
    .accessibilityIdentifier("googleSignInButton")
    .background {
      AuthenticationPresentationAnchor(presenter: presenter)
        .frame(width: 0, height: 0)
    }
    .alert(
      "Googleログイン",
      isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private func signIn() {
    guard let controller = presenter.current() else {
      errorMessage = GoogleAccountSignInError.noPresentationWindow.localizedDescription
      return
    }
    Task {
      do {
        if let account = try await accounts.signIn(presenting: controller) {
          onSignedIn(account)
        }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
