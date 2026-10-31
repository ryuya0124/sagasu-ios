import SwiftUI

@main
struct AndroidFindApp: App {
  @State private var store = FindStore()
  @State private var googleAccounts = GoogleAccountSignIn()
  @AppStorage("appearance") private var appearance = "system"

  var body: some Scene {
    WindowGroup {
      FindRootView(store: store)
        .environment(googleAccounts)
        .tint(.findAccent)
        .preferredColorScheme(
          ProcessInfo.processInfo.arguments.contains("--dark") || appearance == "dark"
            ? .dark : appearance == "light" ? .light : nil
        )
        .onOpenURL { url in
          _ = googleAccounts.handleCallback(url)
        }
        .task {
          guard !ProcessInfo.processInfo.arguments.contains("--demo"),
            NSClassFromString("XCTestCase") == nil
          else { return }
          await googleAccounts.restoreIfNeeded()
        }
    }
  }
}

extension Color {
  static let findGreen = Color(red: 0.17, green: 0.66, blue: 0.36)
}
