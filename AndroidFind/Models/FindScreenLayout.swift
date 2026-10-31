import Foundation

/// Adapt to the current window, not to a device name. A split iPad window and
/// the closed cover of iPhone Duo should use the same compact layout as iPhone.
struct FindScreenLayout: Equatable {
  let isSidebar: Bool
  let panelWidth: CGFloat
  let panelInset: CGFloat
  let bottomInset: CGFloat
  let tabRailWidth: CGFloat

  init(
    width: CGFloat, height: CGFloat, usesAccessibilitySize: Bool = false,
    usesVerticalTabs: Bool = false
  ) {
    isSidebar = width >= 700 && height >= 400
    panelInset = isSidebar ? 16 : FindMyStyleMetrics.compactInset
    bottomInset = isSidebar ? 16 : 8
    tabRailWidth = usesVerticalTabs ? 76 : 0
    panelWidth =
      isSidebar
      ? min(usesAccessibilitySize ? 440 : 380, width - panelInset * 2)
      : max(0, width - panelInset * 2 - tabRailWidth)
  }
}

private enum FindMyStyleMetrics {
  static let compactInset: CGFloat = 10
}
