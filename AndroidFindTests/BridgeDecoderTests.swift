import XCTest

@testable import AndroidFind

final class BridgeDecoderTests: XCTestCase {
  func testMetadataAndStatusDecodeWithValidatedFields() throws {
    let devices = try XCTUnwrap(
      BridgeDecoder.devices(from: [
        "devices": [
          [
            "id": "one", "name": "Pixel 9",
            "information": [
              "model": "Pixel 9", "manufacturer": "Google", "codeName": "tokay",
              "carrier": "Test Carrier", "imei": "123456789012345", "meid": "",
              "firstRegisteredAt": 1_700_000_000.5,
              "supportedActions": ["sound", "secure", "unexpected"], "opaque": "do-not-copy",
            ],
          ]
        ]
      ]))
    var device = try XCTUnwrap(devices.first)
    XCTAssertEqual(device.information?.model, "Pixel 9")
    XCTAssertEqual(device.information?.supportedActions, ["sound", "secure"])
    XCTAssertEqual(device.information?.firstRegisteredAt?.timeIntervalSince1970, 1_700_000_000.5)
    XCTAssertNil(device.information?.meid)
    BridgeDecoder.applyLocation(
      [
        "battery": 80, "isCharging": true, "wifiSignal": 4, "cellularSignal": 99,
        "network": " Test Wi-Fi ", "cellularNetwork": "Test Mobile",
      ], to: &device)
    XCTAssertEqual(device.isCharging, true)
    XCTAssertEqual(device.wifiSignal, 4)
    XCTAssertNil(device.cellularSignal)
    XCTAssertEqual(device.network, "Test Wi-Fi")
    XCTAssertEqual(device.cellularNetwork, "Test Mobile")
    XCTAssertNil(device.coordinate)
    let encoded = try JSONEncoder().encode(device)
    XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("do-not-copy"))
  }

  func testCacheFromPreviousAppVersionStillDecodesWithoutMetadata() throws {
    let data = Data(
      #"{"id":"one","name":"Phone","kind":"phone","isCached":false,"isDemo":false}"#.utf8)
    let device = try JSONDecoder().decode(FindDevice.self, from: data)
    XCTAssertEqual(device.id, "one")
    XCTAssertNil(device.information)
    XCTAssertNil(device.isCharging)
    XCTAssertNil(device.statusReceivedAt)
  }

  func testInventoryRejectsMalformedRowsAndDuplicateIDs() {
    let payload: [String: Any] = [
      "devices": [
        ["id": "phone-1", "name": "Pixel", "imageURL": "https://example.com/phone.png"],
        ["id": "phone-1", "name": "Duplicate"],
        ["id": "", "name": "Invalid"],
        ["name": "Missing ID"],
      ]
    ]
    let devices = BridgeDecoder.devices(from: payload)
    XCTAssertEqual(devices?.count, 1)
    XCTAssertEqual(devices?.first?.id, "phone-1")
    XCTAssertEqual(devices?.first?.imageURL?.scheme, "https")
  }

  func testMissingInventoryDiffersFromAnEmptyAccount() {
    XCTAssertNil(BridgeDecoder.devices(from: [:]))
    XCTAssertEqual(BridgeDecoder.devices(from: ["devices": []]), [])
  }

  func testRejectsInvalidCoordinatesWithoutErasingLastKnownPosition() {
    var device = FindDevice(id: "phone", name: "Phone", latitude: 35, longitude: 139)
    BridgeDecoder.applyLocation(
      ["latitude": 900.0, "longitude": 20.0, "battery": 140], to: &device)
    XCTAssertEqual(device.latitude, 35)
    XCTAssertEqual(device.longitude, 139)
    XCTAssertNil(device.battery)
    BridgeDecoder.applyLocation(["latitude": 0.0, "longitude": 0.0, "battery": 0], to: &device)
    XCTAssertEqual(device.coordinate?.latitude, 0)
    XCTAssertEqual(device.coordinate?.longitude, 0)
    XCTAssertEqual(device.battery, 0)
  }

  func testRejectsNonHTTPSImagesAndNonFiniteLocations() {
    let rows = BridgeDecoder.devices(from: [
      "devices": [
        [
          "id": "1", "name": "Phone", "imageURL": "file:///private/data",
        ]
      ]
    ])
    XCTAssertNil(rows?.first?.imageURL)
    var device = FindDevice(id: "1", name: "Phone")
    BridgeDecoder.applyLocation(
      ["latitude": Double.nan, "longitude": Double.infinity], to: &device)
    XCTAssertNil(device.coordinate)
  }
}
