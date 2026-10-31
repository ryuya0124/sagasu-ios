import Foundation
import XCTest

@testable import AndroidFind

final class DeviceCacheTests: XCTestCase {
  private func cache() -> DeviceCache {
    DeviceCache(
      fileURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        .appending(
          path: "cache.json"))
  }

  func testCacheRestoresLocationAndSelectionButExcludesDemoDevicesAndBackup() throws {
    let cache = cache()
    defer { cache.clear() }
    let device = FindDevice(
      id: "real", name: "Real Phone", latitude: 0, longitude: 0, locationReceivedAt: .now)
    try cache.save(devices: [device] + FindDevice.previews, selectedID: device.id)
    let snapshot = try XCTUnwrap(cache.load())
    XCTAssertEqual(snapshot.devices.count, 1)
    XCTAssertEqual(snapshot.devices[0].coordinate?.latitude, 0)
    XCTAssertEqual(snapshot.devices[0].isCached, true)
    XCTAssertEqual(snapshot.selectedID, "real")
    let values = try cache.fileURL.deletingLastPathComponent()
      .resourceValues(forKeys: [
        .isExcludedFromBackupKey
      ])
    XCTAssertEqual(values.isExcludedFromBackup, true)
  }

  func testCorruptOrFutureCacheDoesNotBreakLaunch() throws {
    let cache = cache()
    defer { cache.clear() }
    try cache.save(devices: [], selectedID: nil)
    try Data("invalid JSON".utf8).write(to: cache.fileURL)
    XCTAssertNil(cache.load())
    let future = DeviceCache.Snapshot(version: 99, devices: [], selectedID: nil)
    try JSONEncoder().encode(future).write(to: cache.fileURL)
    XCTAssertNil(cache.load())
  }

  func testInventoryMergeUpdatesMetadataPreservingPositionAndRemovingDeletedDevices() {
    let previous = [
      FindDevice(
        id: "one", name: "Old", latitude: 35, longitude: 139, battery: 60, place: "Test Place"),
      FindDevice(id: "removed", name: "Removed"),
    ]
    let incoming = [
      FindDevice(id: "one", name: "Renamed", kind: .tablet), FindDevice(id: "new", name: "New"),
    ]
    let merged = FindDevice.mergingInventory(incoming, previous: previous)
    XCTAssertEqual(merged.map(\.id), ["one", "new"])
    XCTAssertEqual(merged.first?.name, "Renamed")
    XCTAssertEqual(merged.first?.kind, .tablet)
    XCTAssertEqual(merged.first?.coordinate?.latitude, 35)
    XCTAssertEqual(merged.first?.place, "Test Place")
  }

  func testOldAndCachedPositionsAreNotPresentedAsJustSeen() {
    let time = Date(timeIntervalSince1970: 1_700_000_000)
    var device = FindDevice(
      id: "one", name: "Phone", latitude: 35, longitude: 139, lastSeen: "たった今",
      locationReceivedAt: time)
    XCTAssertEqual(device.activityText(at: time), "たった今")
    XCTAssertTrue(device.activityText(at: time.addingTimeInterval(3600)).hasPrefix("前回の取得"))
    device.isCached = true
    XCTAssertTrue(device.activityText(at: time).hasPrefix("前回の取得"))
  }
}
