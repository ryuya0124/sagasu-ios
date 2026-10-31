import SwiftUI
import WebKit

struct GoogleWebView: UIViewRepresentable {
  let session: any FindSession
  func makeUIView(context: Context) -> WKWebView { session.webView }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct GoogleConnectionView: View {
  let session: any FindSession
  var action: DeviceActionRequest? = nil
  var actionMessage: String? = nil
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var bluetooth = PasskeyBluetooth()

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ProgressView()
          .progressViewStyle(.linear)
          .frame(height: 2)
          .opacity(session.isLoading ? 1 : 0)
        if let action {
          VStack(spacing: 4) {
            Label(action.deviceName, systemImage: action.action.symbol)
              .font(
                .subheadline.weight(.semibold))
            Text(actionMessage ?? "Googleの確認画面で続けてください。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(12)
          .background(.bar)
        }
        if session.isPasskeyPage {
          HStack(alignment: .center, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
            Text(bluetooth.message)
              .font(.caption)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if bluetooth.authorization == .denied || bluetooth.authorization == .restricted {
              Button("設定") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
            } else {
              Button(bluetooth.authorization == .notDetermined ? "Bluetoothを許可" : "状態を確認") {
                bluetooth.request()
              }
            }
          }
          .font(.caption)
          .padding(12)
          .background(.bar)
          .accessibilityIdentifier("passkeyBluetoothPermission")
        }
        GoogleWebView(session: session)
          .accessibilityHidden(false)
        Text(
          action == nil
            ? "ご自身のGoogleアカウントでログインしてください。Googleの確認が終わると、デバイス一覧を表示します。"
            : "操作はGoogleの画面で確定します。閉じるだけでは完了しません。"
        )
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(13)
        .background(.bar)
      }
      .navigationTitle(action?.action.title ?? "Googleに接続")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          HStack(spacing: 12) {
            Button {
              session.goBack()
            } label: {
              Image(systemName: "chevron.left")
            }
            .disabled(!session.canGoBack)
            .accessibilityLabel("Google画面で戻る")
            Button("閉じる") { dismiss() }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            session.loadHome()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .accessibilityLabel("Googleを再読み込み")
        }
      }
      .task { session.start() }
    }
  }
}
