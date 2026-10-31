import Foundation
import Security
import XCTest

@testable import AndroidFind

final class GoogleCredentialVaultTests: XCTestCase {
  private func vault() -> GoogleCredentialVault {
    GoogleCredentialVault(service: "dev.ryuya.AndroidFind.credentials-tests.\(UUID().uuidString)")
  }

  func testNothingIsSavedWithoutExplicitConsent() throws {
    let vault = vault()
    defer { try? vault.removeAll() }
    XCTAssertThrowsError(
      try vault.save(email: "person@example.com", password: "synthetic", consent: false))
    XCTAssertNil(try vault.load(email: "person@example.com"))
    XCTAssertNil(try vault.takeForAttempt(email: "person@example.com"))
  }

  func testAccountIsolationAndPerAccountRemoval() throws {
    let vault = vault()
    defer { try? vault.removeAll() }
    try vault.save(email: " Person@Example.com ", password: " synthetic ", consent: true)
    XCTAssertEqual(try vault.load(email: "person@example.com")?.password, " synthetic ")
    XCTAssertNil(try vault.load(email: "another@example.com"))
    try vault.save(email: "another@example.com", password: "another-synthetic", consent: true)
    try vault.remove(email: "person@example.com")
    XCTAssertNil(try vault.load(email: "person@example.com"))
    XCTAssertNotNil(try vault.load(email: "another@example.com"))
    try vault.removeAll()
    XCTAssertNil(try vault.load(email: "another@example.com"))
  }

  func testAutomaticAttemptsAreRateLimitedAcrossVaultInstances() throws {
    let vault = vault()
    defer { try? vault.removeAll() }
    let now = Date()
    try vault.save(email: "person@example.com", password: "synthetic", consent: true, now: now)
    XCTAssertNotNil(try vault.takeForAttempt(email: "person@example.com", now: now))
    let restored = GoogleCredentialVault(service: vault.service)
    XCTAssertNil(
      try restored.takeForAttempt(email: "person@example.com", now: now.addingTimeInterval(899)))
    XCTAssertNotNil(
      try restored.takeForAttempt(email: "person@example.com", now: now.addingTimeInterval(900)))
  }

  func testSavedCredentialCannotSynchronizeAndIsAvailableOnlyWhileUnlockedOnThisDevice() throws {
    let vault = vault()
    defer { try? vault.removeAll() }
    try vault.save(email: "person@example.com", password: "synthetic", consent: true)
    var result: CFTypeRef?
    let status = SecItemCopyMatching(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: vault.service,
        kSecAttrAccount as String: "person@example.com",
        kSecReturnAttributes as String: true,
      ] as CFDictionary, &result)
    XCTAssertEqual(status, errSecSuccess)
    let attributes = try XCTUnwrap(result as? [String: Any])
    XCTAssertEqual(
      attributes[kSecAttrAccessible as String] as? String,
      kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    XCTAssertNotEqual(attributes[kSecAttrSynchronizable as String] as? Bool, true)
  }
}
