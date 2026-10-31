# 探す — Sagasu for iOS

Android端末をiPhone・iPadから確認する、SwiftUI製の非公式クライアントです。Google Find Hubの公式Webクライアントを利用し、取得した端末情報をMapKitとネイティブの一覧に表示します。

GoogleやAppleの公式アプリではありません。現在のソースは **0.8.1（20）**、TestFlightの登録名は「探す - Android端末」です。

## 機能

- Googleアカウントの端末一覧、端末画像、取得できた位置・電池・接続状態の表示
- 一覧表示時の位置の順次取得と、手動選択した端末の優先取得
- 標準地図／航空写真、2D／3D、3段階の下部パネル
- ライト／ダーク表示、端末検索、大きな文字への対応
- 取得できた機種・メーカー・通信事業者・IMEIなどの表示
- サウンド、紛失モード、紛失マーク解除、消去のGoogle公式操作画面への接続
- 前回の端末情報のローカル保存と、アカウント変更時のデータ分離
- 接続開始から直接Find Hubの公式Web画面でログイン
- iPadの左側パネル、iPhone Duoの開閉・回転に応じた配置と縦タブ

端末画像はGoogleが提供するものを使用します。取得できない情報は補って表示せず、前回の位置には古い情報であることを示します。リモート操作の最終確認はGoogleの画面で行います。

## ビルド

必要なものはmacOS、Xcode 27.2以降とXcodeGenです。実行対象はiOS 18以降のiPhone・iPadです。Duoの縦タブはiOS 27.1以降のシステム設定を参照します。

```sh
xcodegen generate
open AndroidFind.xcodeproj
```

`AndroidFind`スキームをシミュレーターで実行します。開発者アカウントなしでもシミュレーター用のアドホック署名で起動できます。

```sh
bash Scripts/run-simulator.sh
bash Scripts/run-simulator.sh --demo
bash Scripts/run-simulator.sh --demo --dark
bash Scripts/run-simulator.sh --demo --detail
```

通常の起動では架空の端末を表示しません。デモの端末・位置情報はサンプルです。

### 実機の署名

```sh
cp Configuration/Signing.example.xcconfig Configuration/Signing.local.xcconfig
```

`Signing.local.xcconfig`の`DEVELOPMENT_TEAM`を自身のApple Developer Team IDに変更してください。別アプリとしてビルドする場合は、`project.yml`のBundle IDも自身の識別子に変更し、XcodeGenで再生成します。

個別の署名設定はGitの対象外です。公開プロジェクトは`Configuration/Signing.xcconfig`の任意インクルードを通して読み込みます。

### Googleログイン

接続ボタンから直接Find Hubを開き、そのGoogle画面でログインします。Googleプロフィール用の先行ログインや、Google CloudのOAuth設定は不要です。[接続方式と制約](Documentation/GoogleSignIn.md)を参照してください。

## テストと整形

Swiftの回帰テスト57件と、JavaScriptのブリッジテスト32件を含みます。

```sh
node --test Scripts/bridge.test.cjs Scripts/login-bridge.test.cjs
xcodebuild -project AndroidFind.xcodeproj -scheme AndroidFind \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
swift-format lint --strict --recursive AndroidFind AndroidFindTests Scripts/GenerateIcon.swift
npx --yes prettier@3.6.2 --check AndroidFind/Resources/*.js Scripts/*.cjs
```

整形設定は`.swift-format`と`.prettierrc.json`で共有しています。

## コードの構成

| ファイル／ディレクトリ | 責務 |
| --- | --- |
| `App/AndroidFindApp.swift` | アプリの起動と外観 |
| `Views/FindRootView.swift` | 地図の選択、各画面、シートの連携 |
| `Views/FindPanel.swift` | ドラッグの開始・追跡・終了・キャンセル |
| `Models/FindPanelLayout.swift` | パネルの高さの上限・下限と停止位置 |
| `Models/FindScreenLayout.swift` / `Views/FindSystemBarLayout.swift` | ウィンドウ幅とシステムのバー位置への追従 |
| `Views/FindMapView.swift` / `FindMapControls.swift` | 地図描画と表示切り替え |
| `Views/DeviceListView.swift` / `DeviceRow.swift` | 端末一覧と行の表示 |
| `Views/DeviceArtwork.swift` / `DeviceMapPin.swift` | Googleの端末画像と地図マーカー |
| `Views/FindTabBar.swift` / `FindSecondaryPanel.swift` | タブと補助画面 |
| `Views/AccountView.swift` / `GoogleConnectionView.swift` | アカウント設定と接続画面 |
| `Services/LegacyGoogleSignInSession.swift` | 旧版のプロフィール認証情報だけをローカルで削除 |
| `Services/FindStore.swift` | 端末の選択、位置取得、アカウント別の状態管理 |
| `Services/GoogleFindSession.swift` | WebKitの接続とネイティブUIへのイベント通知 |
| `Resources/FindHubBridge.js` | Google Webクライアントの端末情報・操作のアダプター |
| `Services/*Vault.swift` | キーチェーンでの保存と復元 |

表中のアプリのファイルは`AndroidFind/`以下にあります。ドラッグは画面座標で測り、追跡中はアニメーションを使わず、終了時だけ高さを確定します。一覧のスクロールにパネルのジェスチャーを重ねません。

## 認証とデータ

端末検索はGoogle Find HubのWebクライアントに依存します。Web側の仕様変更で接続できなくなる場合があります。一般的なGoogleプロフィール認証と、Find Hubの端末情報を取得する権限は別です。

セッションと、明示的に同意して設定した場合の自動ログイン用パスワードは、この端末のキーチェーンに保存します。保存は初期状態で無効です。設定から削除でき、ログアウトやアカウント切り替えでも解除します。コード・ログへパスワードや認証コードを埋め込みません。端末情報のキャッシュにはファイル保護を設定し、バックアップ対象から除外します。

Googleへの認証と端末取得には同じFind Hub用Webセッションを使います。WKWebViewでのGoogleパスキー認証には制約があり、Bluetooth権限の付与だけでは解決しません。Googleの画面で利用できない認証方法がある場合は「別の方法」を選んでください。[Appleのパスキー仕様](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)と[GoogleのiOS向けログイン](https://developers.google.com/identity/sign-in/ios/start-integrating)を参照してください。

iPadとDuoの参考資料・配置規則は[画面レイアウト](Documentation/AdaptiveLayout.md)にまとめています。

## 配布用の設定

`Distribution/Examples/`に署名とアプリ情報の設定例があります。自身のTeam IDなどを設定してから、ローカルの`Distribution/`へコピーします。

App Store Connect APIの秘密鍵はリポジトリ外で管理し、`Scripts/app-store-connect.rb`へ`ASC_KEY_PATH`、`ASC_KEY_ID`、`ASC_ISSUER_ID`を環境変数で渡します。署名済みIPAは次のスクリプトで検証できます。

```sh
python3 Scripts/validate-internal-package.py /path/to/AndroidFind.ipa 20
```

実データ、認証情報、スクリーンショット、調査用データ、署名済みIPA、アーカイブ、ローカル配布設定は公開対象から除外しています。アプリの独自アイコンは`Scripts/GenerateIcon.swift`から生成できます。
