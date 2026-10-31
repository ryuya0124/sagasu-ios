import Foundation

/// Last-known device data stays in this app's protected, non-backed-up local storage.
/// Google session credentials are stored separately in Keychain.
struct DeviceCache {
  struct Snapshot: Codable {
    var version = 1
    var devices: [FindDevice]
    var selectedID: String?
    var accountEmail: String?
  }

  let fileURL: URL

  init(fileURL: URL? = nil) {
    self.fileURL =
      fileURL
      ?? URL.applicationSupportDirectory
      .appending(path: "AndroidFind", directoryHint: .isDirectory)
      .appending(path: "LastDevices.json")
  }

  func load() -> Snapshot? {
    guard let data = try? Data(contentsOf: fileURL),
      var snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.version == 1
    else { return nil }
    var seen = Set<String>()
    snapshot.devices = snapshot.devices
      .filter {
        !$0.isDemo && !$0.id.isEmpty && !$0.name.isEmpty && seen.insert($0.id).inserted
      }
      .map { device in
        var device = device
        device.isCached = true
        if device.imageURL?.scheme != "https" { device.imageURL = nil }
        return device
      }
    if !snapshot.devices.contains(where: { $0.id == snapshot.selectedID }) {
      snapshot.selectedID = nil
    }
    snapshot.accountEmail = GoogleAccountIdentity.normalized(snapshot.accountEmail)
    return snapshot
  }

  func save(devices: [FindDevice], selectedID: String?, accountEmail: String? = nil) throws {
    let real = devices.filter { !$0.isDemo }
    let snapshot = Snapshot(
      devices: real, selectedID: real.contains { $0.id == selectedID } ? selectedID : nil,
      accountEmail: GoogleAccountIdentity.normalized(accountEmail))
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var excludedDirectory = directory
    try excludedDirectory.setResourceValues(values)
    try JSONEncoder().encode(snapshot)
      .write(
        to: fileURL, options: [.atomic, .completeFileProtection])
  }

  func clear() {
    try? FileManager.default.removeItem(at: fileURL)
  }
}
