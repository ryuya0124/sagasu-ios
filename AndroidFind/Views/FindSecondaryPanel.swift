import SwiftUI

/// Panels for the other tabs share the same drawer, without changing list selection.
struct FindSecondaryPanel: View {
  @Bindable var store: FindStore
  let tab: FindTab
  @ScaledMetric(relativeTo: .title2) private var headerSize: CGFloat = 27

  var body: some View {
    if tab == .me {
      mePanel
    } else {
      auxiliaryPanel
    }
  }

  private var mePanel: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Text("自分")
            .font(.system(size: headerSize, weight: .bold))
          Spacer()
          Button {
            store.showAccount = true
          } label: {
            Image(systemName: "info.circle")
              .font(.title3)
              .frame(width: 40, height: 40)
          }
          .accessibilityLabel("アカウントと表示の設定")
        }
        FindMyCard {
          VStack(alignment: .leading, spacing: 13) {
            LabeledContent("アカウント", value: "Google")
            Divider()
            LabeledContent("接続", value: store.isDemo ? "デモ" : store.google.status)
            Divider()
            if store.google.isConnected {
              Button("Google画面を開く") { store.connect() }
                .frame(minHeight: 36)
            } else {
              GoogleSignInButton { account in
                store.selectGoogleAccount(account.email)
              }
            }
          }
          .font(.body)
          .padding(16)
        }
      }
      .padding(.horizontal, 22)
      .padding(.bottom, 16)
    }
    .scrollIndicators(.hidden)
  }

  private var auxiliaryPanel: some View {
    VStack(spacing: 0) {
      HStack {
        Text(tab.rawValue)
          .font(.system(size: headerSize, weight: .bold))
        Spacer()
        Button {
          store.connect()
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 23))
            .frame(width: 40, height: 40)
            .background(.quaternary.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Google画面を開く")
      }
      .padding(.horizontal, 22)
      Spacer(minLength: 15)
      VStack(spacing: 12) {
        Image(systemName: tab == .people ? "figure.2" : "circle.grid.2x2.fill")
          .font(.system(size: 36))
          .foregroundStyle(.secondary)
        Text(tab == .people ? "共有中の人を確認" : "持ち物を確認")
          .font(.headline)
        Text(tab == .people ? "位置情報の共有はGoogle画面で確認できます。" : "Find Hub対応の持ち物はGoogle画面で確認できます。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button("Google画面を開く") { store.connect() }.font(.body)
      }
      .padding(.horizontal, 28)
      Spacer(minLength: 15)
    }
  }

}
