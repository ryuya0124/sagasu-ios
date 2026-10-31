import SwiftUI

@main
struct AndroidFindApp: App {
  @State private var store = FindStore()
  @AppStorage("appearance") private var appearance = "system"

  var body: some Scene {
    WindowGroup {
      FindRootView(store: store)
        .tint(.findAccent)
        .preferredColorScheme(
          ProcessInfo.processInfo.arguments.contains("--dark") || appearance == "dark"
            ? .dark : appearance == "light" ? .light : nil
        )
    }
  }
}

extension Color {
  static let findGreen = Color(red: 0.17, green: 0.66, blue: 0.36)
}
