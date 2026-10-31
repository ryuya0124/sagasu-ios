import CoreBluetooth
import Observation
import UIKit

@MainActor
@Observable
final class PasskeyBluetooth: NSObject, @preconcurrency CBCentralManagerDelegate {
  private(set) var hasRequested = false
  private(set) var state: CBManagerState = .unknown
  @ObservationIgnored private var manager: CBCentralManager?

  var authorization: CBManagerAuthorization { CBManager.authorization }
  var message: String {
    switch authorization {
    case .denied, .restricted: return "パスキーを使うには、設定でBluetoothを許可してください。"
    case .notDetermined: return "近くの端末のパスキーを使う場合は、Bluetoothを許可してください。"
    case .allowedAlways:
      switch state {
      case .poweredOff: return "このiPhoneのBluetoothをオンにしてください。"
      case .unsupported: return "この端末ではBluetoothを利用できません。"
      case .poweredOn: return "Bluetoothは利用できます。認証する端末を近くに置いてください。"
      default: return "Bluetoothの状態を確認しています…"
      }
    @unknown default: return "Bluetoothの設定を確認してください。"
    }
  }

  func request() {
    hasRequested = true
    if manager == nil {
      // Initialization requests authorization. Device scanning and connections remain
      // owned by the system's passkey flow; this app does not enumerate peripherals.
      manager = CBCentralManager(
        delegate: self, queue: .main,
        options: [CBCentralManagerOptionShowPowerAlertKey: false])
    } else if let manager {
      state = manager.state
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) { state = central.state }
}
