import Foundation
import XCTest

@testable import AndroidFind

private actor ImageFetchCounter {
  var calls = 0
  func fetch(_ data: Data?) -> Data? {
    calls += 1
    return data
  }
}

private actor SuspendedImageFetch {
  private var completion: CheckedContinuation<Data?, Never>?
  private var started: CheckedContinuation<Void, Never>?
  func fetch() async -> Data? {
    await withCheckedContinuation { continuation in
      completion = continuation
      started?.resume()
      started = nil
    }
  }
  func waitForStart() async {
    if completion != nil { return }
    await withCheckedContinuation { started = $0 }
  }
  func finish(_ data: Data) {
    completion?.resume(returning: data)
    completion = nil
  }
}

final class DeviceImageRepositoryTests: XCTestCase {
  private let png = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="
  )!
  private let url = URL(string: "https://example.com/model.png")!

  func testSharesDownloadsAndRestoresImageFromDiskOffline() async throws {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let counter = ImageFetchCounter()
    let data = png
    let imageURL = url
    let repository = DeviceImageRepository(directory: directory) { _ in await counter.fetch(data) }
    async let first = repository.data(for: imageURL)
    async let second = repository.data(for: imageURL)
    let results = await [first, second]
    XCTAssertEqual(results, [png, png])
    let calls = await counter.calls
    XCTAssertEqual(calls, 1)
    let offline = DeviceImageRepository(directory: directory) { _ in nil }
    let restored = await offline.data(for: url)
    XCTAssertEqual(restored, png)
  }

  func testRejectsInvalidImagesAndAuthenticatedOrNonHTTPSURLs() async {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let counter = ImageFetchCounter()
    let repository = DeviceImageRepository(directory: directory) { _ in
      await counter.fetch(Data("not an image".utf8))
    }
    let insecure = await repository.data(for: URL(string: "http://example.com/image.png")!)
    let authenticated = await repository.data(
      for: URL(string: "https://user:password@example.com/a.png")!)
    XCTAssertNil(insecure)
    XCTAssertNil(authenticated)
    let before = await counter.calls
    XCTAssertEqual(before, 0)
    let invalid = await repository.data(for: url)
    XCTAssertNil(invalid)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }

  func testSignOutInvalidatesAnImageDownloadAlreadyInFlight() async {
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = SuspendedImageFetch()
    let imageURL = url
    let repository = DeviceImageRepository(directory: directory) { _ in await gate.fetch() }
    let request = Task { await repository.data(for: imageURL) }
    await gate.waitForStart()
    await repository.removeAll()
    await gate.finish(png)
    let result = await request.value
    XCTAssertNil(result)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
  }
}
