import Foundation

enum GoogleFindSignInURL {
  static let browserHome = URL(string: "https://www.google.com/android/find/?hl=ja")!

  static func home(accountEmail: String?) -> URL {
    guard let email = GoogleAccountIdentity.normalized(accountEmail) else { return browserHome }
    var parts = URLComponents(url: browserHome, resolvingAgainstBaseURL: false)!
    // This is an account hint, not an OAuth token or a claim that Find Hub is authorized.
    parts.queryItems?.append(URLQueryItem(name: "authuser", value: email))
    return parts.url ?? browserHome
  }
}
