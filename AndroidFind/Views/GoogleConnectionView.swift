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
            Image(systemName: "key.horizontal")
            Text("この接続画面ではパスキーを使用できません。Googleの「別の方法」で続けるか、ブラウザ版を開いてください。")
              .font(.caption)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("ブラウザ版") {
              openURL(GoogleFindSignInURL.browserHome)
            }
          }
          .font(.caption)
          .padding(12)
          .background(.bar)
          .accessibilityIdentifier("passkeyBrowserRecovery")
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
