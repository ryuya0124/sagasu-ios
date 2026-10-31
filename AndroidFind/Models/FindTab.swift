import Foundation

enum FindTab: String, CaseIterable {
  case people = "人を探す"
  case devices = "デバイスを探す"
  case items = "持ち物を探す"
  case me = "自分"

  var symbol: String {
    switch self {
    case .people: "figure.2"
    case .devices: "laptopcomputer.and.iphone"
    case .items: "circle.grid.2x2.fill"
    case .me: "location.fill"
    }
  }
}
