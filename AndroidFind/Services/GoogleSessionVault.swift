import Foundation
import Security

/// Keeps this app's own Google web session in the device Keychain.
/// Passwords, authentication codes, Chrome cookies and location data never enter this store.
struct GoogleSessionVault {
  let service: String
  private let account = "google-web-session"

  init(service: String = "dev.ryuya.AndroidFind.google-session") {
    self.service = service
  }

  func save(_ cookies: [HTTPCookie]) throws {
    try saveData(CookieSnapshot.encode(cookies), account: account)
  }

  func load() throws -> [HTTPCookie] {
    guard let data = try loadData(account: account) else { return [] }
    return try CookieSnapshot.decode(data)
  }

  func saveEntryURL(_ url: URL) throws {
    guard let url = GoogleSessionEntry.restorableURL(url) else { return }
    try saveData(Data(url.absoluteString.utf8), account: "google-entry-url")
  }

  func loadEntryURL() throws -> URL? {
    guard let data = try loadData(account: "google-entry-url"),
      let text = String(data: data, encoding: .utf8), let url = URL(string: text)
    else { return nil }
    return GoogleSessionEntry.restorableURL(url)
  }

  func delete() {
    for account in [account, "google-entry-url"] {
      SecItemDelete(query(account: account) as CFDictionary)
    }
  }

  private func query(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func saveData(_ data: Data, account: String) throws {
    let query = query(account: account)
    let result = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if result == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      let inserted = SecItemAdd(item as CFDictionary, nil)
      guard inserted == errSecSuccess else { throw VaultError(status: inserted) }
    } else if result != errSecSuccess {
      throw VaultError(status: result)
    }
  }

  private func loadData(account: String) throws -> Data? {
    var query = query(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let result = SecItemCopyMatching(query as CFDictionary, &item)
    if result == errSecItemNotFound { return nil }
    guard result == errSecSuccess, let data = item as? Data else {
      throw VaultError(status: result)
    }
    return data
  }

  struct VaultError: Error {
    let status: OSStatus
  }
}

/// Some Google sign-in flows return an access-token entry URL rather than SID cookies.
/// Accept only this service's HTTPS origin; the entire URL remains in Keychain.
enum GoogleSessionEntry {
  static func restorableURL(_ url: URL) -> URL? {
    guard url.scheme == "https", url.host == "www.google.com",
      url.user == nil, url.password == nil, url.port == nil || url.port == 443,
      url.path == "/android/find" || url.path == "/android/find/"
        || url.path.hasPrefix("/android/find/device/"),
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let token = parts.queryItems?.first(where: { $0.name == "access_token" })?.value,
      !token.isEmpty, token.count <= 16_384
    else { return nil }
    return url
  }
}

enum CookieSnapshot {
  private struct Record: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Date?
    let secure: Bool
    let httpOnly: Bool
    let version: Int
    let sameSite: String?

    init(_ cookie: HTTPCookie) {
      name = cookie.name
      value = cookie.value
      domain = cookie.domain
      path = cookie.path
      expires = cookie.expiresDate
      secure = cookie.isSecure
      httpOnly = cookie.isHTTPOnly
      version = cookie.version
      sameSite = cookie.properties?[.sameSitePolicy] as? String
    }

    func cookie() -> HTTPCookie? {
      var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name, .value: value, .domain: domain, .path: path, .version: version,
      ]
      if let expires { properties[.expires] = expires }
      if secure { properties[.secure] = "TRUE" }
      if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
      if let sameSite { properties[.sameSitePolicy] = sameSite }
      return HTTPCookie(properties: properties)
    }
  }

  static func isGoogleDomain(_ domain: String) -> Bool {
    let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return host == "google.com" || host.hasSuffix(".google.com")
  }

  static func hasAuthenticationCookies(_ cookies: [HTTPCookie]) -> Bool {
    cookies.contains {
      isGoogleDomain($0.domain)
        && ["SID", "__Secure-1PSID", "__Secure-3PSID"].contains($0.name)
    }
  }

  static func encode(_ cookies: [HTTPCookie]) throws -> Data {
    let records = cookies.filter { isGoogleDomain($0.domain) }.map(Record.init)
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    return try encoder.encode(records)
  }

  static func decode(_ data: Data, now: Date = .now) throws -> [HTTPCookie] {
    let records = try PropertyListDecoder().decode([Record].self, from: data)
    return records.compactMap { record in
      guard isGoogleDomain(record.domain), record.expires.map({ $0 > now }) ?? true else {
        return nil
      }
      return record.cookie()
    }
  }
}
