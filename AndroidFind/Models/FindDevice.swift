import CoreLocation
import Foundation

struct FindDevice: Identifiable, Equatable, Codable, Sendable {
  enum Kind: String, Codable, Sendable {
    case phone, tablet, watch, earbuds, tag
  }

  let id: String
  var name: String
  var kind: Kind = .phone
  var imageURL: URL?
  var information: DeviceInformation?
  var latitude: Double?
  var longitude: Double?
  var battery: Int?
  var connectionStatus: String?
  var isCharging: Bool?
  var network: String?
  var cellularNetwork: String?
  var wifiSignal: Int?
  var cellularSignal: Int?
  var lastSeen: String?
  var place: String?
  var locationReceivedAt: Date?
  var statusReceivedAt: Date?
  var isCached = false
  var isDemo = false

  var coordinate: CLLocationCoordinate2D? {
    guard let latitude, let longitude,
      latitude.isFinite, longitude.isFinite,
      (-90...90).contains(latitude), (-180...180).contains(longitude)
    else { return nil }
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  var subtitle: String {
    place ?? connectionStatus ?? (coordinate == nil ? "位置情報を取得していません" : "Google Find Hub の位置情報")
  }

  var batterySymbol: String {
    guard let battery else { return "battery.0percent" }
    switch battery {
    case 0..<10: return "battery.0percent"
    case 10..<35: return "battery.25percent"
    case 35..<60: return "battery.50percent"
    case 60..<85: return "battery.75percent"
    default: return "battery.100percent"
    }
  }

  func activityText(at date: Date = .now) -> String {
    if let receivedAt = locationReceivedAt,
      isCached || date.timeIntervalSince(receivedAt) > 120
    {
      let formatter = RelativeDateTimeFormatter()
      formatter.locale = Locale(identifier: "ja_JP")
      return "前回の取得・" + formatter.localizedString(for: receivedAt, relativeTo: date)
    }
    return connectionStatus ?? lastSeen ?? (coordinate == nil ? "位置情報は未取得" : "位置情報を取得済み")
  }

  static func mergingInventory(_ incoming: [FindDevice], previous: [FindDevice]) -> [FindDevice] {
    let known = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return incoming.map { device in
      guard var old = known[device.id] else { return device }
      old.name = device.name
      old.kind = device.kind
      old.imageURL = device.imageURL ?? old.imageURL
      old.information = device.information ?? old.information
      return old
    }
  }

  static let previews: [FindDevice] = [
    FindDevice(
      id: "demo-galaxy", name: "Galaxy S26 Ultra",
      latitude: 35.6814, longitude: 139.7671, battery: 85,
      network: "自宅の Wi-Fi", lastSeen: "たった今", place: "自宅", isDemo: true
    ),
    FindDevice(
      id: "demo-pixel", name: "Google Pixel 10", latitude: 35.6835,
      longitude: 139.7695, battery: 62, lastSeen: "3分前", place: "近くにあります", isDemo: true
    ),
    FindDevice(
      id: "demo-watch", name: "Pixel Watch", kind: .watch,
      latitude: 35.6792, longitude: 139.7645, battery: 48,
      lastSeen: "12分前", place: "丸の内", isDemo: true
    ),
    FindDevice(
      id: "demo-buds", name: "Pixel Buds", kind: .earbuds,
      latitude: 35.6816, longitude: 139.7680,
      lastSeen: "1時間前", place: "最後に確認された場所", isDemo: true
    ),
  ]
}

struct DeviceInformation: Equatable, Codable, Sendable {
  var model: String?
  var manufacturer: String?
  var codeName: String?
  var carrier: String?
  var imei: String?
  var meid: String?
  var firstRegisteredAt: Date?
  var supportedActions: [String]?
}

/// Accepts only the narrow, noncredential payload produced by our WebKit bridge.
enum BridgeDecoder {
  static func devices(from payload: [String: Any]) -> [FindDevice]? {
    guard let rows = payload["devices"] as? [[String: Any]] else { return nil }
    var seen: Set<String> = []
    return rows.compactMap { row in
      guard let id = row["id"] as? String, !id.isEmpty,
        let name = row["name"] as? String, !name.isEmpty,
        seen.insert(id).inserted
      else { return nil }
      let imageURL = (row["imageURL"] as? String).flatMap(URL.init(string:))
      let details = row["information"] as? [String: Any]
      let information = details.map { details in
        DeviceInformation(
          model: string(details["model"]), manufacturer: string(details["manufacturer"]),
          codeName: string(details["codeName"]), carrier: string(details["carrier"]),
          imei: string(details["imei"]), meid: string(details["meid"]),
          firstRegisteredAt: date(details["firstRegisteredAt"]),
          supportedActions: (details["supportedActions"] as? [String])?
            .filter {
              ["sound", "secure", "erase", "rename"].contains($0)
            })
      }
      return FindDevice(
        id: id,
        name: name,
        kind: FindDevice.Kind(rawValue: row["kind"] as? String ?? "") ?? .phone,
        imageURL: imageURL?.scheme == "https" && imageURL?.user == nil && imageURL?.password == nil
          ? imageURL : nil,
        information: information
      )
    }
  }

  static func applyLocation(_ payload: [String: Any], to device: inout FindDevice) {
    if let latitude = payload["latitude"] as? Double,
      let longitude = payload["longitude"] as? Double,
      latitude.isFinite, longitude.isFinite,
      (-90...90).contains(latitude), (-180...180).contains(longitude)
    {
      device.latitude = latitude
      device.longitude = longitude
    }
    if let battery = payload["battery"] as? Int, (0...100).contains(battery) {
      device.battery = battery
    }
    device.isCharging = payload["isCharging"] as? Bool
    device.connectionStatus = string(payload["connectionStatus"])
    device.network = string(payload["network"])
    device.cellularNetwork = string(payload["cellularNetwork"])
    device.wifiSignal = signal(payload["wifiSignal"])
    device.cellularSignal = signal(payload["cellularSignal"])
    device.lastSeen = string(payload["lastSeen"])
  }

  private static func string(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && trimmed.count <= 512 ? trimmed : nil
  }

  private static func date(_ value: Any?) -> Date? {
    guard let seconds = value as? Double, seconds.isFinite,
      seconds > 0, seconds < 253_402_300_800
    else { return nil }
    return Date(timeIntervalSince1970: seconds)
  }

  private static func signal(_ value: Any?) -> Int? {
    guard let value = value as? Int, (0...4).contains(value) else { return nil }
    return value
  }
}
