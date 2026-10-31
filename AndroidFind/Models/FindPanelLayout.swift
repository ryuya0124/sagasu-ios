import Foundation

enum FindPanelDetent: CaseIterable {
  case compact
  case medium
  case expanded

  var accessibilityDescription: String {
    switch self {
    case .compact: "縮小"
    case .medium: "標準"
    case .expanded: "拡大"
    }
  }
}

/// Shared bounds for drawing the panel and settling a completed drag.
struct FindPanelLayout: Equatable {
  let compactHeight: CGFloat
  let mediumHeight: CGFloat
  let maximumHeight: CGFloat

  init(
    viewportHeight: CGFloat,
    bottomInset: CGFloat,
    showsDetail: Bool,
    usesAccessibilitySize: Bool
  ) {
    maximumHeight = max(0, viewportHeight + bottomInset - 28)
    compactHeight =
      usesAccessibilitySize ? maximumHeight : min(showsDetail ? 151 : 160, maximumHeight)
    mediumHeight =
      usesAccessibilitySize ? maximumHeight : min(showsDetail ? 450 : 410, maximumHeight)
  }

  func height(for detent: FindPanelDetent) -> CGFloat {
    switch detent {
    case .compact: compactHeight
    case .medium: mediumHeight
    case .expanded: maximumHeight
    }
  }

  func height(startingAt startHeight: CGFloat, translation: CGFloat) -> CGFloat {
    clamped(startHeight - translation)
  }

  func destination(
    startingAt startHeight: CGFloat,
    translation: CGFloat,
    predictedTranslation: CGFloat
  ) -> FindPanelDetent {
    // Bound the extra momentum so a fast flick cannot project far outside the screen.
    let momentum = min(max(predictedTranslation - translation, -100), 100)
    let proposedHeight = clamped(
      height(startingAt: startHeight, translation: translation) - momentum)

    return FindPanelDetent.allCases.min {
      abs(height(for: $0) - proposedHeight) < abs(height(for: $1) - proposedHeight)
    } ?? .medium
  }

  private func clamped(_ height: CGFloat) -> CGFloat {
    min(max(height, compactHeight), maximumHeight)
  }
}
