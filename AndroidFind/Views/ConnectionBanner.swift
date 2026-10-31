import SwiftUI

struct ConnectionBanner: View {
  let store: FindStore

  var body: some View {
    if !store.isDemo {
      if store.google.isAutomaticallySigningIn {
        HStack(spacing: 9) {
          ProgressView()
            .controlSize(.small)
          Text("自動で再ログイン中…")
            .font(.caption)
          Spacer(minLength: 0)
        }
        .padding(12)
        .foregroundStyle(.secondary)
      } else if let message = store.google.connectionError ?? store.inventoryError {
        banner(message, symbol: "wifi.exclamationmark", warning: true) {
          if store.google.connectionError != nil {
            store.retryConnection()
          } else {
            store.refresh()
          }
        }
      } else if store.google.requiresSignIn {
        banner(
          "Googleへのログインが必要です", symbol: "person.crop.circle.badge.exclamationmark", warning: true
        ) {
          store.connect()
        }
      } else if store.google.isLoading || store.google.isRefreshing {
        HStack(spacing: 9) {
          ProgressView()
            .controlSize(.small)
          Text(store.google.isLoading ? "Googleに接続中…" : "デバイスを更新中…")
          Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func banner(_ message: String, symbol: String, warning: Bool, retry: @escaping () -> Void)
    -> some View
  {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(warning ? .orange : Color.findGreen)
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(
          horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Button(store.google.requiresSignIn ? "ログイン" : "再試行", action: retry)
        .font(.caption.weight(.semibold))
        .buttonStyle(.borderless)
        .frame(minHeight: 36)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
  }
}
