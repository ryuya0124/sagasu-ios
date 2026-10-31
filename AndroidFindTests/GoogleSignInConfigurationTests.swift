import XCTest

@testable import AndroidFind

final class GoogleSignInConfigurationTests: XCTestCase {
  private let clientID = "123456789-test.apps.googleusercontent.com"
  private let scheme = "com.googleusercontent.apps.123456789-test"

  func testRequiresTheMatchingRegisteredCallbackForTheIOSClient() throws {
    let configuration = try XCTUnwrap(GoogleSignInConfiguration(info: info()))
    XCTAssertEqual(configuration.clientID, clientID)
    XCTAssertEqual(configuration.callbackScheme, scheme)
    XCTAssertTrue(
      configuration.acceptsCallback(URL(string: "\(scheme):/oauthredirect?state=test")!))
    XCTAssertFalse(configuration.acceptsCallback(URL(string: "https://accounts.google.com/")!))
    XCTAssertFalse(configuration.acceptsCallback(URL(string: "unrelated:/oauthredirect")!))
    var missingCallback = info()
    missingCallback["CFBundleURLTypes"] = []
    XCTAssertNil(GoogleSignInConfiguration(info: missingCallback))
  }

  func testRejectsUnconfiguredAndMalformedClientIDs() {
    for invalid in [
      "", "YOUR_CLIENT_ID", ".apps.googleusercontent.com", clientID + " ",
      "https://" + clientID, "123.apps.googleusercontent.com.evil.example",
    ] {
      var values = info()
      values["GIDClientID"] = invalid
      XCTAssertNil(GoogleSignInConfiguration(info: values))
    }
  }

  func testFindHubAccountHintDoesNotContainCredentialsAndPreservesTheOfficialOrigin() throws {
    let url = GoogleFindSignInURL.home(accountEmail: "Person+test@example.com")
    let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(url.host, "www.google.com")
    XCTAssertEqual(url.scheme, "https")
    XCTAssertEqual(
      parts.queryItems?.first(where: { $0.name == "authuser" })?.value,
      "person+test@example.com")
    XCTAssertFalse(parts.queryItems?.contains(where: { $0.name == "access_token" }) ?? true)
    XCTAssertEqual(
      GoogleFindSignInURL.home(accountEmail: "invalid"), GoogleFindSignInURL.browserHome)
  }

  private func info() -> [String: Any] {
    [
      "GIDClientID": clientID,
      "CFBundleURLTypes": [["CFBundleURLSchemes": [scheme]]],
    ]
  }
}
