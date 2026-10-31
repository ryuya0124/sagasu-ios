import MapKit
import SwiftUI

struct DeviceDetailView: View {
  @Bindable var store: FindStore
  let device: FindDevice
  @State private var pendingAction: DeviceActionRequest?
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .title2) private var headerSize: CGFloat = 27

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
          .padding(.horizontal, 10)
          .padding(.bottom, 3)
        ConnectionBanner(store: store)
        actionButtons
        lostDevice
        if let message = store.locationError {
          Label(message, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
        }
        deviceInformation
        locationInformation
        hardwareInformation
        if device.isDemo {
          Text("デモの端末・位置情報です")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 22)
    }
    .scrollIndicators(.hidden)
    .accessibilityIdentifier("deviceDetail")
    .confirmationDialog(
      pendingAction?.action.title ?? "デバイスの操作",
      isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
      titleVisibility: .visible, presenting: pendingAction
    ) { request in
      Button("Googleで確認", role: request.action == .erase ? .destructive : nil) {
        store.openDeviceAction(request)
      }
      Button("キャンセル", role: .cancel) { pendingAction = nil }
    } message: { request in
      Text("対象：\(request.deviceName)\n\(request.action.explanation)\nGoogleの画面で最終確認します。")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 8) {
        Text(device.name)
          .font(.system(size: headerSize, weight: .bold))
          .lineLimit(2)
          .minimumScaleFactor(0.8)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button {
          withAnimation(.spring(duration: 0.35)) { store.closeDevice() }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .background(.quaternary.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("デバイス一覧に戻る")
        .padding(.top, -3)
      }
      Text(device.place ?? (device.coordinate == nil ? "位置情報が見つかりません" : "位置情報を取得済み"))
        .font(.body)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      TimelineView(.periodic(from: .now, by: 60)) { context in
        HStack(spacing: 7) {
          if store.isLocating {
            ProgressView()
              .controlSize(.mini)
          }
          let activity = device.activityText(at: context.date)
          Text(store.isLocating && device.coordinate == nil ? "位置情報を検索中…" : activity)
            .foregroundStyle(!device.isCached && activity == "たった今" ? Color.green : .secondary)
          if let battery = device.battery {
            Text("·")
              .foregroundStyle(.secondary)
            Image(systemName: device.batterySymbol)
              .font(.system(size: 13))
              .foregroundStyle(battery <= 20 ? .red : .secondary)
              .accessibilityLabel("電池残量 \(battery)パーセント")
          }
        }
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      }
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: 12) {
        soundAction
        directionsAction
      }
    } else {
      HStack(spacing: 12) {
        soundAction
        directionsAction
      }
    }
  }

  private var soundAction: some View {
    action(
      title: store.soundState == .playing ? "サウンドを停止" : "サウンドを再生",
      subtitle: store.soundState == .sending ? "接続中…" : store.soundState == .playing ? "再生中" : "オフ",
      symbol: store.soundState == .playing ? "stop.fill" : "play.fill",
      color: FindMyStyle.sound, isLoading: store.soundState == .sending
    ) { store.playSound() }
    .disabled(!store.canOperateDevice || store.soundState == .sending)
  }

  private var directionsAction: some View {
    action(
      title: "経路", subtitle: "マップで表示", symbol: "arrow.turn.up.right", color: FindMyStyle.directions
    ) {
      openDirections()
    }
    .disabled(device.coordinate == nil)
  }

  private var lostDevice: some View {
    FindMyCard {
      VStack(alignment: .leading, spacing: 10) {
        FindMyBadge(symbol: "questionmark", color: .orange)
        Text(lostTitle)
          .font(.body.weight(.semibold))
        Divider()
          .padding(.top, 6)
        Button {
          guard !store.isDemo else {
            store.notice = "デモでは端末のリモートロックを実行できません。"
            return
          }
          openURL(URL(string: "https://www.google.com/android/find/lock?hl=ja")!)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
              Text("電話番号でリモートロック")
                .font(.body)
              Text("Google公式画面に対象の電話番号を入力")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(.tertiary)
          }
          .padding(.vertical, 7)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("remoteLockByPhone")
        Divider()
        deviceActionRow(.lock, subtitle: "端末をロックして連絡先を表示")
        Divider()
        deviceActionRow(.markFound, subtitle: "見つかった端末の紛失のマークを解除")
        Divider()
        deviceActionRow(.erase, subtitle: "すべてのデータを消去", destructive: true)
        Text("Googleで利用できる操作を確認できます。")
          .font(.caption)
          .foregroundStyle(.secondary)

      }
      .padding(16)
    }
  }

  private func deviceActionRow(_ action: DeviceAction, subtitle: String, destructive: Bool = false)
    -> some View
  {
    Button {
      pendingAction = store.actionRequest(action)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: action.symbol)
          .font(.body)
          .frame(width: 24)
          .foregroundStyle(destructive ? Color.red : Color.primary)
        VStack(alignment: .leading, spacing: 3) {
          Text(action.title)
            .font(.body)
            .foregroundStyle(destructive ? Color.red : Color.primary)
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("deviceAction-" + action.rawValue)
  }

  private var lostTitle: String {
    switch device.kind {
    case .phone: "スマートフォンを紛失"
    case .tablet: "タブレットを紛失"
    case .watch: "ウォッチを紛失"
    default: "デバイスを紛失"
    }
  }

  private var deviceInformation: some View {
    FindMyCard {
      VStack(alignment: .leading, spacing: 10) {
        FindMyBadge(symbol: "info", color: .gray)
        Text("デバイス情報")
          .font(.body.weight(.semibold))
        Divider()
          .padding(.top, 6)
        if let status = device.connectionStatus { informationRow("接続状態", status) }
        if let network = device.network, !network.isEmpty {
          informationRow("Wi-Fi", network)
        }
        if let signal = device.wifiSignal {
          informationRow("Wi-Fiの信号レベル", String(signal))
        }
        if let network = device.cellularNetwork {
          informationRow("モバイルデータ", network)
        }
        if let signal = device.cellularSignal {
          informationRow("モバイルの信号レベル", String(signal))
        }
        if let battery = device.battery {
          informationRow("バッテリー", "\(battery)%")
        }
        if let charging = device.isCharging {
          informationRow("充電", charging ? "充電中" : "充電していません")
        }
        if let lastSeen = device.lastSeen {
          informationRow("最終検知", lastSeen)
        }
        if let received = device.statusReceivedAt {
          informationRow("状態の取得日時", formatted(received))
        }
        Button("位置情報を更新") { store.refresh() }
          .font(.body)
          .frame(minHeight: 36, alignment: .leading)
          .disabled(store.isLocating || store.google.isLoading)
      }
      .padding(16)
    }
  }

  @ViewBuilder
  private var locationInformation: some View {
    if let coordinate = device.coordinate {
      FindMyCard {
        VStack(alignment: .leading, spacing: 12) {
          Label("位置情報", systemImage: "location.fill")
            .font(.body.weight(.semibold))
          Divider()
          if let place = device.place { informationRow("住所", place) }
          informationRow("緯度", String(format: "%.7f", coordinate.latitude))
          informationRow("経度", String(format: "%.7f", coordinate.longitude))
          if let date = device.locationReceivedAt {
            informationRow("位置の取得日時", formatted(date))
          }
          informationRow("取得元", "Google Find Hub")
          if device.isCached {
            Label("前回保存した位置情報", systemImage: "clock")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        .padding(16)
      }
    }
  }

  private var hardwareInformation: some View {
    FindMyCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 14) {
          DeviceArtwork(device: device, size: 60)
          VStack(alignment: .leading, spacing: 4) {
            Text("このデバイスについて")
              .font(.body.weight(.semibold))
            Text(device.name)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        Divider()
        if let details = device.information {
          if let model = details.model { informationRow("機種", model) }
          if let manufacturer = details.manufacturer { informationRow("メーカー", manufacturer) }
          if let codeName = details.codeName { informationRow("デバイスコード", codeName) }
          if let carrier = details.carrier { informationRow("通信事業者", carrier) }
          if let date = details.firstRegisteredAt {
            informationRow(
              "初回登録日",
              date.formatted(
                Date.FormatStyle(date: .numeric, time: .omitted)
                  .locale(Locale(identifier: "ja_JP"))))
          }
          if let imei = details.imei { informationRow("IMEI", imei) }
          if let meid = details.meid { informationRow("MEID", meid) }
          if let actions = details.supportedActions, !actions.isEmpty {
            let titles = actions.compactMap {
              ["sound": "音を鳴らす", "secure": "端末を保護", "erase": "データを消去", "rename": "名前を変更"][$0]
            }
            informationRow("対応する操作", titles.joined(separator: "・"))
          }
        }
        informationRow("デバイスID", device.id)
      }
      .padding(16)
    }
  }

  private func informationRow(_ title: String, _ value: String) -> some View {
    LabeledContent {
      Text(value)
        .lineLimit(nil)
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    } label: {
      Text(title)
        .foregroundStyle(.secondary)
    }
    .font(.subheadline)
    .contextMenu {
      Button("コピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
    }
  }

  private func formatted(_ date: Date) -> String {
    date.formatted(
      Date.FormatStyle(date: .numeric, time: .standard)
        .locale(Locale(identifier: "ja_JP")))
  }

  private func action(
    title: String, subtitle: String, symbol: String, color: Color,
    isLoading: Bool = false, perform: @escaping () -> Void
  ) -> some View {
    Button(action: perform) {
      FindMyCard {
        VStack(alignment: .leading, spacing: 8) {
          if isLoading {
            ProgressView()
              .tint(color)
              .frame(width: 28, height: 28)
          } else {
            FindMyBadge(symbol: symbol, color: color)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.body.weight(.semibold))
              .foregroundStyle(.primary)
              .lineLimit(2)
              .minimumScaleFactor(0.8)
            Text(subtitle)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(16)
      }
      .contentShape(RoundedRectangle(cornerRadius: FindMyStyle.cardRadius))
    }
    .buttonStyle(.plain)
  }

  private func openDirections() {
    guard let coordinate = device.coordinate else { return }
    let item: MKMapItem
    if #available(iOS 26.0, *) {
      item = MKMapItem(
        location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
        address: nil)
    } else {
      item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    }
    item.name = device.name
    item.openInMaps(launchOptions: [
      MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
    ])
  }
}
