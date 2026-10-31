import SwiftUI

struct AccountView: View {
  @Bindable var store: FindStore
  @State private var showAutomaticLogin = false
  @AppStorage("appearance") private var appearance = "system"
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
              .font(.system(size: 44))
              .foregroundStyle(.gray.opacity(0.6))
            VStack(alignment: .leading, spacing: 5) {
              Text(store.accountEmail ?? "Googleアカウント")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
              Text(store.google.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
          Button(store.google.isConnected ? "Find Hubを開く" : "Find Hubに接続") {
            store.connect()
          }
          .accessibilityIdentifier("findHubConnectButton")
          if store.accountEmail != nil {
            Button {
              showAutomaticLogin = true
            } label: {
              LabeledContent("自動ログイン", value: store.automaticLoginEnabled ? "設定済み" : "オフ")
            }
          }
          if store.google.isConnected || store.accountEmail != nil {
            Button("このアプリからログアウト", role: .destructive) {
              Task { await store.disconnect() }
            }
          }
        }
        Section {
          Picker("外観", selection: $appearance) {
            Text("システム")
              .tag("system")
            Text("ライト")
              .tag("light")
            Text("ダーク")
              .tag("dark")
          }
          Toggle(
            "デモを表示",
            isOn: Binding(
              get: { store.isDemo },
              set: { if $0 { store.enableDemo() } else { store.leaveDemo() } }
            ))
        } footer: {
          Text("デモの端末と位置情報はサンプルです。実際のデバイスの検索にはGoogleへのログインが必要です。")
        }
        Section {
          NavigationLink("プライバシーとデータ", destination: PrivacyView())
          LabeledContent("接続中のデバイス", value: "\(store.google.devices.count)台")
          LabeledContent(
            "バージョン",
            value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
        } footer: {
          Text("前回取得した端末と位置はこのデバイスに保存され、ログアウトすると削除されます。")
        }
      }
      .sheet(isPresented: $showAutomaticLogin) { AutomaticLoginSettingsView(store: store) }
      .navigationTitle("アカウント")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
    }
  }
}
