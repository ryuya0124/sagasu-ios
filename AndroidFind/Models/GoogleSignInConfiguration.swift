import Foundation

/// An iOS OAuth client identifies this app; it is separate from Find Hub's Web session.
struct GoogleSignInConfiguration: Equatable, Sendable {
  let clientID: String
  let callbackScheme: String

  init?(info: [String: Any]) {
    guard let clientID = info["GIDClientID"] as? String,
      clientID.hasSuffix(".apps.googleusercontent.com"),
      clientID.count > ".apps.googleusercontent.com".count,
      clientID.count <= 256,
      clientID.unicodeScalars.allSatisfy({
        CharacterSet(
          charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."
        )
        .contains($0)
      })
    else { return nil }

    let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")
    let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
    let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    guard schemes.contains(where: { $0.caseInsensitiveCompare(scheme) == .orderedSame }) else {
      return nil
    }
    self.clientID = clientID
    callbackScheme = scheme
  }

  func acceptsCallback(_ url: URL) -> Bool {
    url.scheme?.caseInsensitiveCompare(callbackScheme) == .orderedSame
  }
}

struct GoogleAccountProfile: Equatable, Sendable {
  let email: String
  let name: String?

  init?(email: String, name: String? = nil) {
    guard let email = GoogleAccountIdentity.normalized(email) else { return nil }
    self.email = email
    self.name = name
  }
}

enum GoogleAccountSignInError: LocalizedError {
  case notConfigured
  case noPresentationWindow
  case missingProfile
  case cancelled
  case unavailable

  var errorDescription: String? {
    switch self {
    case .notConfigured: "Googleログインの設定が必要です。開発者の設定を確認してください。"
    case .noPresentationWindow: "ログイン画面を開けませんでした。もう一度お試しください。"
    case .missingProfile: "Googleアカウントのメールアドレスを確認できませんでした。"
    case .cancelled: nil
    case .unavailable: "Googleにログインできませんでした。通信環境を確認して、もう一度お試しください。"
    }
  }
}
