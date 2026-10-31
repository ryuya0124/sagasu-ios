import SwiftUI

/// Open the same Find Hub session that supplies device data, without a separate identity sign-in.
struct FindHubConnectionButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text("Find Hubに接続")
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .accessibilityIdentifier("findHubConnectButton")
  }
}
