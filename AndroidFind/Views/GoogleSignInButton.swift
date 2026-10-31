import SwiftUI

struct GoogleSignInButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Text("G")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(
            AngularGradient(
              colors: [.blue, .green, .yellow, .red, .blue], center: .center
            ))
        Text("Googleでログイン")
          .font(.system(size: 16, weight: .semibold))
      }
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity)
      .frame(height: 49)
      .background(.background, in: Capsule())
      .overlay(
        Capsule()
          .stroke(.gray.opacity(0.22), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("googleSignInButton")
  }
}
