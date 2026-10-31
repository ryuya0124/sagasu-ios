# iPad・iPhone Duoの画面レイアウト

iPadはAppleがApp Storeに掲載している「探す」のiPad画像を参考にしています。地図を背景に、左側に幅を抑えた独立パネルを置き、上部のハンドルで高さを切り替えます。公式画像そのものはアプリや公開リポジトリへ組み込みません。

Duo専用の「探す」の実画面は、調査した公開資料では確認できていません。Duoの配置はAppleのHuman Interface Guidelinesと技術資料を基準にしています。純正アプリとの完全一致を検証したものではありません。

## 配置の規則

- ウィンドウが幅700pt以上、高さ400pt以上なら、幅380ptの左側パネルを使います。アクセシビリティサイズの文字では440ptです。
- 狭いウィンドウでは下部パネルになります。iPadの分割表示も同じ幅の規則で切り替えます。
- iOS 27.1以降の`toolbarVerticalEdge`に値がある場合、その側へ縦タブを置きます。Duoの外側画面と内側の横画面で使われます。
- 内側の縦画面など、システムが縦バーを指定しない場合は下タブに戻ります。
- 開閉や回転で選択中の端末・タブを作り直しません。機種名での判定はしません。

画面幅の単体テストと、Duoシミュレーターでの開閉・回転確認は別に実施します。シミュレーターでの確認は実機での動作確認を意味しません。

## 参考資料

- [Apple「探す」App Store](https://apps.apple.com/jp/app/id1514844621) — iPad向けの公式画像
- [Apple: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Apple: Raise the bar with iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111462/)
