@preconcurrency import GoogleSignIn

/// Remove the identity-only credentials saved by 0.8.0. This local SDK sign-out
/// does not delete Find Hub's WebView session or sign the person out of Safari.
@MainActor
enum LegacyGoogleSignInSession {
  static func clear() {
    GIDSignIn.sharedInstance.signOut()
  }
}
