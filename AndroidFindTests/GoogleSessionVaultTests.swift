import Foundation
import WebKit
import XCTest

@testable import AndroidFind

final class GoogleSessionVaultTests: XCTestCase {
  private func cookie(
    name: String, domain: String = ".google.com", expires: Date? = nil, httpOnly: Bool = false
  ) -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [
      .name: name, .value: "synthetic-test-value", .domain: domain, .path: "/", .secure: "TRUE",
    ]
    if let expires { properties[.expires] = expires }
    if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
    return HTTPCookie(properties: properties)!
  }

  func testCookieSnapshotRetainsSessionCookiesAndProtectionFlags() throws {
    let original = cookie(name: "TestSession", httpOnly: true)
    let restored = try CookieSnapshot.decode(CookieSnapshot.encode([original]))
    XCTAssertEqual(restored.count, 1)
    XCTAssertEqual(restored.first?.value, original.value)
    XCTAssertEqual(restored.first?.isSecure, true)
    XCTAssertEqual(restored.first?.isHTTPOnly, true)
    XCTAssertNil(restored.first?.expiresDate)
  }

  func testSnapshotExcludesOtherDomainsAndExpiredCookies() throws {
    let data = try CookieSnapshot.encode([
      cookie(name: "valid", domain: "accounts.google.com", expires: .now.addingTimeInterval(3600)),
      cookie(name: "expired", expires: .now.addingTimeInterval(-3600)),
      cookie(name: "unrelated", domain: "other.example"),
      cookie(name: "lookalike", domain: "evilgoogle.com"),
    ])
    XCTAssertEqual(try CookieSnapshot.decode(data).map(\.name), ["valid"])
  }

  func testKeychainRoundTripAndLocalSignOutRemoval() throws {
    let vault = GoogleSessionVault(service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)")
    defer { vault.delete() }
    XCTAssertTrue(try vault.load().isEmpty)
    try vault.save([cookie(name: "test-session", httpOnly: true)])
    XCTAssertEqual(try vault.load().first?.name, "test-session")
    let entry = URL(
      string: "https://www.google.com/android/find/?access_token=synthetic-test-token")!
    try vault.saveEntryURL(entry)
    XCTAssertEqual(try vault.loadEntryURL(), entry)
    vault.delete()
    XCTAssertTrue(try vault.load().isEmpty)
    XCTAssertNil(try vault.loadEntryURL())
  }

  func testSessionEntryRejectsOtherOriginsAndMissingTokens() {
    for text in [
      "http://www.google.com/android/find/?access_token=test",
      "https://www.google.com.evil.example/android/find/?access_token=test",
      "https://accounts.google.com/android/find/?access_token=test",
      "https://www.google.com/other/?access_token=test",
      "https://www.google.com/android/find-other/?access_token=test",
      "https://www.google.com/android/find/about?access_token=test",
      "https://www.google.com/android/find/settings?access_token=test",
      "https://www.google.com/android/find/?hl=ja",
      "https://www.google.com/android/find/?access_token=",
      "https://user@www.google.com/android/find/?access_token=test",
    ] {
      XCTAssertNil(GoogleSessionEntry.restorableURL(URL(string: text)!))
    }
  }

  @MainActor
  func testWebKitSnapshotIncludesSecureHTTPOnlyAuthenticationCookie() async throws {
    // Isolated jar: synthetic authentication values are never sent over the network.
    let store = WKWebsiteDataStore(forIdentifier: UUID())
    let vault = GoogleSessionVault(service: "dev.ryuya.AndroidFind.tests.\(UUID().uuidString)")
    defer { vault.delete() }
    let original = try XCTUnwrap(
      HTTPCookie.cookies(
        withResponseHeaderFields: [
          "Set-Cookie":
            "SID=synthetic-test-value; Domain=.google.com; Path=/; Secure; HttpOnly; SameSite=None"
        ],
        for: URL(string: "https://www.google.com/")!
      )
      .first)
    await store.httpCookieStore.setCookie(original)
    let collected = await store.httpCookieStore.allCookies()
    XCTAssertTrue(CookieSnapshot.hasAuthenticationCookies(collected))
    try vault.save(collected)
    let restored = try vault.load()
    XCTAssertTrue(CookieSnapshot.hasAuthenticationCookies(restored))
    XCTAssertEqual(restored.first?.isHTTPOnly, true)
    XCTAssertEqual(restored.first?.isSecure, true)
    await store.removeData(
      ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
  }
}
