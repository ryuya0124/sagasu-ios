import CryptoKit
import Foundation
import ImageIO

/// Stores only the device images supplied by Google. No browser cookies or session tokens
/// are attached to these public image requests.
actor DeviceImageRepository {
  static let shared = DeviceImageRepository()
  private let directory: URL
  private let fetch: @Sendable (URL) async -> Data?
  private var memory: [URL: Data] = [:]
  private var pending: [URL: Task<Data?, Never>] = [:]
  private var generation = UUID()

  init(
    directory: URL = URL.cachesDirectory.appending(
      path: "DeviceImages", directoryHint: .isDirectory),
    fetch: @escaping @Sendable (URL) async -> Data? = DeviceImageRepository.download
  ) {
    self.directory = directory
    self.fetch = fetch
  }

  func data(for url: URL) async -> Data? {
    guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
      return nil
    }
    if let cached = memory[url] { return cached }
    let file = fileURL(for: url)
    if let cached = try? Data(contentsOf: file), Self.isImage(cached) {
      memory[url] = cached
      return cached
    }
    let token = generation
    if let task = pending[url] {
      let downloaded = await task.value
      guard generation == token, let downloaded, Self.isImage(downloaded) else { return nil }
      return downloaded
    }
    let loader = fetch
    let task = Task { await loader(url) }
    pending[url] = task
    let downloaded = await task.value
    guard generation == token else { return nil }
    pending[url] = nil
    guard let downloaded, Self.isImage(downloaded) else { return nil }
    memory[url] = downloaded
    if memory.count > 64 { memory = [url: downloaded] }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try downloaded.write(to: file, options: [.atomic, .completeFileProtection])
    } catch {
      // A temporary disk failure must not hide an image already downloaded.
    }
    return downloaded
  }

  func removeAll() {
    generation = UUID()
    for task in pending.values { task.cancel() }
    pending.removeAll()
    memory.removeAll()
    try? FileManager.default.removeItem(at: directory)
  }

  private func fileURL(for url: URL) -> URL {
    let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }
      .joined()
    return directory.appending(path: digest + ".image")
  }

  private static func isImage(_ data: Data) -> Bool {
    guard !data.isEmpty, data.count <= 4_000_000,
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    else { return false }
    return CGImageSourceGetCount(source) > 0
  }

  private static func download(_ url: URL) async -> Data? {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }
    do {
      let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 20))
      guard let response = response as? HTTPURLResponse, response.statusCode == 200,
        response.url?.scheme == "https", response.mimeType?.hasPrefix("image/") == true
      else { return nil }
      return data
    } catch { return nil }
  }
}
