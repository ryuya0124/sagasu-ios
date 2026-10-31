import SwiftUI

struct AutomaticLoginSettingsView: View {
  @Bindable var store: FindStore
  @State private var expectedEmail: String?
  @State private var password = ""
  @State private var agrees = false
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss

  init(store: FindStore) {
    self.store = store
    _expectedEmail = State(initialValue: store.accountEmail)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Googleアカウント", value: expectedEmail ?? "未接続")
          LabeledContent("自動ログイン", value: store.automaticLoginEnabled ? "設定済み" : "オフ")
        }
        Section("このiPhoneへの保存") {
          Text("同意した場合だけ、GoogleのパスワードをこのiPhoneのキーチェーンに保存します。開発者のサーバーやiCloudには送信しません。")
          Text(
            "保存したパスワードは、Google公式のログイン画面への自動入力に使用します。2段階認証・CAPTCHA・追加の本人確認が必要な場合はGoogle画面を開きます。"
          )
          Text("保存はいつでも削除でき、アプリからログアウトした場合も削除します。")
          SecureField(store.automaticLoginEnabled ? "新しいパスワード" : "Googleのパスワード", text: $password)
            .textContentType(.password)
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(
              .never
            )
            .autocorrectionDisabled()
            .privacySensitive()
            .accessibilityIdentifier("savedGooglePassword")
          Toggle("保存と自動入力に同意する", isOn: $agrees)
            .accessibilityIdentifier("automaticLoginConsent")
          Button("同意して保存") {
            do {
              try store.saveAutomaticLogin(
                password: password, consent: agrees, expectedEmail: expectedEmail ?? "")
              password = ""
              dismiss()
            } catch { failure = "保存できませんでした。入力内容とiPhoneのロック状態を確認してください。" }
          }
          .disabled(
            !agrees || password.isEmpty || expectedEmail == nil
              || expectedEmail != store.accountEmail
          )
          .accessibilityIdentifier("saveAutomaticLogin")
        }
        if store.automaticLoginEnabled {
          Section {
            Button("保存したパスワードを削除", role: .destructive) {
              do {
                try store.removeAutomaticLogin(expectedEmail: expectedEmail ?? "")
                password = ""
                agrees = false
              } catch { failure = "削除できませんでした。もう一度お試しください。" }
            }
          }
        }
        if let failure {
          Section {
            Text(failure)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("自動ログイン")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
    }
    .onChange(of: store.accountEmail) { _, email in
      if email != expectedEmail {
        password = ""
        agrees = false
        failure = "アカウントが変わりました。閉じて設定し直してください。"
      }
    }
    .onDisappear {
      password = ""
      agrees = false
    }
  }
}
