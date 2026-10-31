import SwiftUI

/// Empty, loading and sign-in states for the device list.
struct DeviceConnectionPrompt: View {
  @Bindable var store: FindStore

  var body: some View {
    VStack(spacing: 14) {
      if store.google.isLoading && !store.isDemo {
        ProgressView()
          .controlSize(.large)
          .padding(.top, 20)
        Text("デバイスを読み込み中")
          .font(.headline)
        Text("Googleへの接続を確認しています")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else if store.google.isConnected && !store.isDemo {
        Image(systemName: "iphone.slash")
          .font(.system(size: 40))
          .foregroundStyle(.secondary)
          .padding(.top, 15)
        Text("デバイスがありません")
          .font(.headline)
        Text("Googleアカウントに登録された\nデバイスがここに表示されます。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button("Google画面を開く") { store.connect() }.font(.subheadline.weight(.semibold))
      } else if let message = store.google.connectionError {
        Image(systemName: "wifi.exclamationmark")
          .font(.system(size: 38))
          .foregroundStyle(
            .secondary
          )
          .padding(.top, 15)
        Text("接続できませんでした")
          .font(.headline)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
        Button("もう一度接続") { store.retryConnection() }.buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
      } else {
        Image(systemName: "location.circle.fill")
          .font(.system(size: 46))
          .foregroundStyle(Color.findAccent)
          .padding(.top, 5)
        VStack(spacing: 6) {
          Text("Androidを、ここから。")
            .font(.system(size: 21, weight: .bold))
          Text("Googleアカウントに接続して\nスマートフォンの場所を確認できます。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
        }
        FindHubConnectionButton { store.connect() }
          .padding(.horizontal, 30)
        Button("デモを見てみる") { store.enableDemo() }
          .font(.subheadline.weight(.medium))
          .accessibilityIdentifier("demoButton")
      }
    }
    .frame(maxWidth: .infinity)
  }

}
