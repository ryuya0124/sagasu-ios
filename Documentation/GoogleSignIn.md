# Googleログインの設定

GoogleSignIn-iOS 10.1.0をSwift Package Managerで固定しています。基本プロフィールの認証だけを要求し、Find Hub用のスコープやGoogleの非公開クライアントIDは使いません。

## 開発者の設定

1. Google Cloudで専用プロジェクトを用意し、Google Auth Platformのブランディングと対象ユーザーを設定します。
2. アプリのBundle IDに一致する **iOS** OAuthクライアントを作成します。Team IDは自分のApple Developerチームを指定します。
3. `Configuration/GoogleSignIn.example.xcconfig`を`Configuration/GoogleSignIn.local.xcconfig`へコピーします。
4. `GOOGLE_CLIENT_ID`と、ドット区切りの順序を逆にした`GOOGLE_REVERSED_CLIENT_ID`を指定します。
5. `xcodegen generate`後にビルドします。クライアントシークレットは不要です。

ローカル設定はGitの対象外です。ソースに含まれる設定例だけではGoogleログインは有効になりません。テスト公開中はGoogle側の対象ユーザー設定も確認してください。

## アカウント選択と端末の接続

公式SDKはシステムブラウザーのGoogle認証を開きます。利用できるアカウントや認証方法は、Googleと端末のログイン状態によって変わります。他アプリの保存アカウントを独自に列挙する機能はありません。

Googleプロフィールへのログイン成功と、Google Find Hubの端末情報への接続成功は別です。プロフィールのトークンをFind Hubへ渡したり、SafariのCookieを取り出したりしません。選択したメールアドレスを公式Webページの`authuser`として指定し、Webクライアントから一致するアカウントが確認されるまで端末データを採用しません。別アカウントへ切り替える際は、前のキャッシュ・セッション・同意済み保存パスワードを解除します。

キャンセル時は以前のプロフィールを維持します。ログアウト後に遅れてSDKの認証結果が届いた場合は、その結果も破棄します。認証はボタンを押したウィンドウから表示し、並行した認証画面を開きません。

## パスキー

Google標準ログインは公式SDKのシステムブラウザー経由です。Find Hubを表示するWKWebViewでは、Googleドメインに必要なAssociated Domainsをこのアプリが設定できないため、Googleのパスキー認証を提供できません。Bluetoothの権限要求で代替できるものではありません。

Find Hub側で追加認証が必要な場合は、Googleの「別の方法」を使います。ブラウザー版を開く導線も用意していますが、外部ブラウザーでの認証結果をアプリに取り込む機能ではありません。

## 参考資料

- [Google: iOSでのログイン](https://developers.google.com/identity/sign-in/ios/sign-in)
- [Google: OAuthクライアントとURLスキームの設定](https://developers.google.com/identity/sign-in/ios/start-integrating)
- [Apple: Supporting passkeys](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)
