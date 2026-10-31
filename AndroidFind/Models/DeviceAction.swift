import Foundation

/// These actions open Google's own confirmation flow. They never confirm a remote command.
enum DeviceAction: String, CaseIterable, Identifiable, Sendable {
  case lock, markFound, erase

  var id: String { rawValue }
  var title: String {
    switch self {
    case .lock: "紛失モードでロック"
    case .markFound: "紛失モードを解除"
    case .erase: "このデバイスを消去"
    }
  }
  var symbol: String {
    switch self {
    case .lock: "lock.fill"
    case .markFound: "lock.open.fill"
    case .erase: "trash"
    }
  }
  var explanation: String {
    switch self {
    case .lock: "Googleの「紛失としてマーク」で端末をロックし、連絡先やメッセージを設定できます。"
    case .markFound: "Googleの画面で紛失のマークを解除します。端末の画面ロックの扱いはGoogleの案内を確認してください。"
    case .erase: "実行すると端末のデータが完全に消去され、消去後はFind Hubで位置を確認できなくなります。"
    }
  }
}

struct DeviceActionRequest: Equatable, Identifiable, Sendable {
  let id = UUID()
  let action: DeviceAction
  let deviceID: String
  let deviceName: String
  let accountEmail: String?
}
