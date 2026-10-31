import Foundation
import Security

/// Explicitly opted-in credentials for this app only. Never shared with another device or server.
struct GoogleCredentialVault {
  struct Credential: Codable, Sendable {
    let email: String
    let password: String
    let consentVersion: Int
    let consentedAt: Date
    var lastAttemptAt: Date?
  }
  enum Failure: Error {
    case consentRequired, invalidInput
    case keychain(OSStatus)
  }
  let service: String
  init(service: String = "dev.ryuya.AndroidFind.automatic-login") { self.service = service }

  func save(email: String, password: String, consent: Bool, now: Date = .now) throws {
    guard consent else { throw Failure.consentRequired }
    guard let email = GoogleAccountIdentity.normalized(email), !password.isEmpty,
      password.utf8.count <= 16_384
    else { throw Failure.invalidInput }
    try write(Credential(email: email, password: password, consentVersion: 1, consentedAt: now))
  }

  func load(email: String) throws -> Credential? {
    guard let email = GoogleAccountIdentity.normalized(email) else { return nil }
    var q = query(email: email)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw Failure.keychain(status)
    }
    let value = try PropertyListDecoder().decode(Credential.self, from: data)
    guard value.email == email, value.consentVersion == 1, !value.password.isEmpty else {
      return nil
    }
    return value
  }

  /// Persist the rate limit before returning a credential, including across app restarts.
  func takeForAttempt(email: String, now: Date = .now) throws -> Credential? {
    guard var credential = try load(email: email) else { return nil }
    if let previous = credential.lastAttemptAt, now.timeIntervalSince(previous) < 15 * 60 {
      return nil
    }
    credential.lastAttemptAt = now
    try write(credential)
    return credential
  }

  func remove(email: String) throws {
    guard let email = GoogleAccountIdentity.normalized(email) else { return }
    let status = SecItemDelete(query(email: email) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Failure.keychain(status)
    }
  }

  func removeAll() throws {
    let status = SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      ] as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Failure.keychain(status)
    }
  }

  private func query(email: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: email, kSecAttrSynchronizable as String: false,
    ]
  }

  private func write(_ value: Credential) throws {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    let data = try encoder.encode(value)
    let q = query(email: value.email)
    let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = q
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      let added = SecItemAdd(item as CFDictionary, nil)
      guard added == errSecSuccess else { throw Failure.keychain(added) }
    } else if status != errSecSuccess {
      throw Failure.keychain(status)
    }
  }
}
