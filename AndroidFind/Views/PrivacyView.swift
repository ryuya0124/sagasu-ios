import SwiftUI

struct PrivacyView: View {
  var body: some View {
    List {
      Section("Googleへの接続") {
        Text(
          "Googleアカウントの選択にはGoogle公式SDKとシステムの認証画面を使用します。アカウント選択後、必要に応じてFind Hubへの接続を確認します。Googleプロフィールへのログインと、端末情報への接続は別に管理します。"
        )
        Text(
          "自分のGoogleアカウントに登録された端末を検索します。ログインと本人確認はGoogleの公式Web画面で行います。通常はパスワードを保存しません。「自動ログイン」で同意して保存した場合だけ、このデバイスのキーチェーンに保存してGoogleのログイン画面へ自動入力します。確認コードは保存しません。"
        )
        Text("ログイン状態は、このデバイスのキーチェーンとアプリ専用のWeb保存領域に保存します。Googleがログインを無効にした場合は、再ログインが必要です。")
      }
      Section("このデバイスに保存する情報") {
        Text("前回取得した端末情報・最終位置・接続したアカウント・端末画像を保存し、次回の起動時に表示します。開発者のサーバーへ送信する仕組みや広告・アクセス解析はありません。")
        Text(
          "アカウントの切り替えやログアウトでは、このアプリに保存した端末・位置・ログイン状態・同意して保存したパスワードを削除します。Googleアカウント自体やAndroid端末のデータは削除しません。"
        )
      }
      Section("パスキー") {
        Text(
          "Googleの標準ログインではシステムの認証画面を使用します。端末検索の接続画面ではパスキーを使用できない場合があり、Googleの別の認証方法またはブラウザ版をご利用いただけます。このアプリ自身がBluetooth機器を検索することはありません。"
        )
      }
      Section("利用するサービス") {
        Text(
          "端末の検索にはGoogle Find Hub、地図と住所の検索にはAppleのマップサービスを使います。このアプリはGoogleやAppleが提供する公式アプリではありません。"
        )
        Link(
          "Googleのプライバシーポリシー",
          destination: URL(string: "https://policies.google.com/privacy?hl=ja")!)
        Link(
          "Appleのプライバシーポリシー", destination: URL(string: "https://www.apple.com/jp/legal/privacy/")!)
      }
    }
    .navigationTitle("プライバシーとデータ")
    .navigationBarTitleDisplayMode(.inline)
  }
}
