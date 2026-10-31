import UIKit
import XCTest

@testable import AndroidFind

@MainActor
private final class GoogleAccountProviderStub: GoogleAccountProviding {
  var profile = GoogleAccountProfile(email: "person@example.com", name: "Person")!
  var restored: GoogleAccountProfile?
  var failure: GoogleAccountSignInError?
  var suspendSignIn = false
  var signInCalls = 0
  var restoreCalls = 0
  var signOutCalls = 0
  private var pending: CheckedContinuation<GoogleAccountProfile, Error>?
  private var started: CheckedContinuation<Void, Never>?

  func signIn(presenting: UIViewController) async throws -> GoogleAccountProfile {
    signInCalls += 1
    if let failure { throw failure }
    if suspendSignIn {
      return try await withCheckedThrowingContinuation { continuation in
        pending = continuation
        started?.resume()
        started = nil
      }
    }
    return profile
  }

  func waitForStart() async {
    if pending != nil { return }
    await withCheckedContinuation { started = $0 }
  }

  func completeSignIn() {
    pending?.resume(returning: profile)
    pending = nil
  }

  func restore() async throws -> GoogleAccountProfile? {
    restoreCalls += 1
    if let failure { throw failure }
    return restored
  }

  func signOut() { signOutCalls += 1 }
  func handleCallback(_ url: URL) -> Bool { false }
}

final class GoogleAccountSignInTests: XCTestCase {
  @MainActor
  func testSilentRestoreRunsOnceAndDoesNotStartInteractiveSignIn() async {
    let provider = GoogleAccountProviderStub()
    provider.restored = provider.profile
    let service = GoogleAccountSignIn(provider: provider)
    await service.restoreIfNeeded()
    await service.restoreIfNeeded()
    XCTAssertEqual(service.account, provider.profile)
    XCTAssertEqual(provider.restoreCalls, 1)
    XCTAssertEqual(provider.signInCalls, 0)
  }

  @MainActor
  func testCancellingAccountSelectionPreservesTheExistingIdentity() async throws {
    let provider = GoogleAccountProviderStub()
    provider.restored = provider.profile
    let service = GoogleAccountSignIn(provider: provider)
    await service.restoreIfNeeded()
    provider.failure = .cancelled
    let selected = try await service.signIn(presenting: UIViewController())
    XCTAssertNil(selected)
    XCTAssertEqual(service.account, provider.profile)
    XCTAssertFalse(service.isWorking)
  }

  @MainActor
  func testSignOutDiscardsAndRemovesALateSuccessfulSDKResult() async throws {
    let provider = GoogleAccountProviderStub()
    provider.suspendSignIn = true
    let service = GoogleAccountSignIn(provider: provider)
    let request = Task { try await service.signIn(presenting: UIViewController()) }
    await provider.waitForStart()
    service.signOut()
    provider.completeSignIn()
    let result = try await request.value
    XCTAssertNil(result)
    XCTAssertNil(service.account)
    XCTAssertEqual(provider.signOutCalls, 2)
    XCTAssertFalse(service.isWorking)
  }

  @MainActor
  func testDoesNotStartTwoSystemAuthenticationSessionsAtOnce() async throws {
    let provider = GoogleAccountProviderStub()
    provider.suspendSignIn = true
    let service = GoogleAccountSignIn(provider: provider)
    let request = Task { try await service.signIn(presenting: UIViewController()) }
    await provider.waitForStart()
    let second = try await service.signIn(presenting: UIViewController())
    XCTAssertNil(second)
    XCTAssertEqual(provider.signInCalls, 1)
    provider.completeSignIn()
    let result = try await request.value
    XCTAssertEqual(result, provider.profile)
  }

  @MainActor
  func testFailedRestoreLeavesTheExplicitSignInAvailable() async throws {
    let provider = GoogleAccountProviderStub()
    provider.failure = .unavailable
    let service = GoogleAccountSignIn(provider: provider)
    await service.restoreIfNeeded()
    XCTAssertNil(service.account)
    XCTAssertFalse(service.isWorking)
    provider.failure = nil
    let result = try await service.signIn(presenting: UIViewController())
    XCTAssertEqual(result, provider.profile)
  }
}
