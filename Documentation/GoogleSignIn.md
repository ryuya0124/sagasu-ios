# Google Find Hubへの接続

0.8.1以降は、接続ボタンから直接Google Find Hubの公式Web画面を開きます。Googleアカウントの選択、ログイン、追加の本人確認、端末情報の取得を同じアプリ専用Webセッションで行います。Googleの画面が表示する利用可能な認証方法を使ってください。

## 接続状態の判定

Googleプロフィールへのログインだけでは接続済みにしません。Find Hubの公式Webクライアントから端末一覧が返った時点で接続済みとし、ページから確認したアカウントと端末データを照合します。別アカウントへ切り替わると、前の端末キャッシュと同意済み保存パスワードを解除します。

0.8.0ではGoogle公式SDKによるプロフィール認証のあと、セッションを共有しないFind Hub用WebViewを開いていたため、再ログインになっていました。この前段の認証は廃止しました。接続済みのFind Hubセッションは引き続き復元します。

## 旧プロフィール認証の整理

GoogleSignIn-iOS 10.1.0は、0.8.0で保存されたアプリ所有のプロフィール認証情報をローカルで削除するためにだけ残しています。`LegacyGoogleSignInSession.clear()`がSDKの`signOut()`を呼びます。新しいSDK認証やサイレント復元は開始せず、SafariやFind Hubのログイン状態は削除しません。

iOS OAuthクライアントIDとSDK用のURLスキームは、接続に使用しません。公開チェックアウトにGoogle Cloudの認証設定を追加する必要もありません。

## 保存済みパスキーについて

対象はGoogle用に保存済みのパスキーで、新しいパスキーやアプリ独自アカウントを作成する機能はありません。

通常のWKWebViewには、RP IDに対するAssociated Domainsと、サイト側のAASA登録が必要です。独自ドメインのAASAだけでは、GoogleのRP IDへのアクセス権は得られません。Bluetooth権限を足すだけでも解決しません。

パスキー画面のURLだけを見て「この接続画面ではパスキーを使用できません」と表示していた固定バナーは削除しました。接続を直接Find Hubへ一本化したことと、パスキー認証そのものが動作することは別です。Googleの画面でパスキーを利用できない場合は「別の方法」での認証が必要です。

## 参考資料

- [Apple: Supporting passkeys](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)
- [Apple: Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains)
- [Google: Sign in with Googleの統合上の考慮事項](https://developers.google.com/identity/siwg/integrate)
