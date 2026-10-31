import Foundation

enum FindTab: String, CaseIterable {
  case people = "人を探す"
  case devices = "デバイスを探す"
  case items = "持ち物を探す"
  case me = "自分"

  var symbol: String {
    switch self {
    case .people: "person.2.fill"
    case .devices: "laptopcomputer.and.iphone"
    case .items: "circle.circle"
    case .me: "location.fill"
    }
  }
}
