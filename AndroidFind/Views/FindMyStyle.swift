import SwiftUI

enum FindMyStyle {
  static let panelRadius: CGFloat = 34
  static let cardRadius: CGFloat = 27
  static let panelInset: CGFloat = 10
  static let panelBottomInset: CGFloat = 8
  static let sound = Color(red: 0.36, green: 0.27, blue: 0.98)
  static let directions = Color(red: 0, green: 0.53, blue: 1)

  // Device photos from Google are transparent. Let the system resolve their backing
  // colors for the current appearance instead of painting a white disk in dark mode.
  static let deviceImageBackground = Color(uiColor: .tertiarySystemFill)
  static let mapMarkerBackground = Color(uiColor: .secondarySystemBackground)
}

extension Color {
  static let findAccent = Color(uiColor: .systemBlue)
}

extension View {
  @ViewBuilder
  func findMyGlass<S: Shape>(in shape: S) -> some View {
    if #available(iOS 26.0, *) {
      self.glassEffect(.regular, in: shape)
    } else {
      self.background(.regularMaterial, in: shape)
        .overlay(shape.stroke(.white.opacity(0.3), lineWidth: 0.5))
    }
  }
}

struct FindMyCard<Content: View>: View {
  @Environment(\.colorScheme) private var colorScheme
  @ViewBuilder let content: Content

  var body: some View {
    content
      .background(
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.62),
        in: RoundedRectangle(cornerRadius: FindMyStyle.cardRadius, style: .continuous))
  }
}

struct FindMyBadge: View {
  let symbol: String
  let color: Color

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 28, height: 28)
      .background(color, in: Circle())
      .accessibilityHidden(true)
  }
}
