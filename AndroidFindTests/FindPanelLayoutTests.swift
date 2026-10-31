import XCTest

@testable import AndroidFind

final class FindPanelLayoutTests: XCTestCase {
  private let layout = FindPanelLayout(
    viewportHeight: 800,
    bottomInset: 34,
    showsDetail: false,
    usesAccessibilitySize: false)

  func testUpwardDragFollowsAbsoluteFingerMovementWithoutAccumulation() {
    let start = layout.height(for: .medium)
    let translations: [CGFloat] = [0, -50, -100, -100, -200, -300]
    let heights = translations.map { layout.height(startingAt: start, translation: $0) }

    XCTAssertEqual(heights, [410, 460, 510, 510, 610, 710])
    XCTAssertEqual(heights[2], heights[3], "A stationary finger must not keep moving the panel")
  }

  func testReversingDirectionUsesTheSameDragOrigin() {
    let start = layout.height(for: .medium)
    let translations: [CGFloat] = [-200, -100, 0, 100]
    let heights = translations.map { layout.height(startingAt: start, translation: $0) }

    XCTAssertEqual(heights, [610, 510, 410, 310])
  }

  func testDraggingPastEitherEdgeStaysInsideTheViewport() {
    XCTAssertEqual(layout.height(startingAt: 410, translation: -10_000), 806)
    XCTAssertEqual(layout.height(startingAt: 410, translation: 10_000), 160)
    XCTAssertEqual(
      layout.destination(startingAt: 410, translation: -10_000, predictedTranslation: -20_000),
      .expanded)
    XCTAssertEqual(
      layout.destination(startingAt: 410, translation: 10_000, predictedTranslation: 20_000),
      .compact)
  }

  func testSmallMovementCannotJumpAcrossTheScreenFromAnExtremeVelocityPrediction() {
    XCTAssertEqual(
      layout.destination(startingAt: 410, translation: -5, predictedTranslation: -100_000),
      .medium)
    XCTAssertEqual(
      layout.destination(startingAt: 410, translation: 5, predictedTranslation: 100_000),
      .medium)
  }

  func testIntentionalFlickAndShortDragSettleAtAppropriateDetents() {
    XCTAssertEqual(
      layout.destination(startingAt: 410, translation: -240, predictedTranslation: -700),
      .expanded)
    XCTAssertEqual(
      layout.destination(startingAt: 160, translation: -170, predictedTranslation: -220),
      .medium)
    XCTAssertEqual(
      layout.destination(startingAt: 410, translation: 180, predictedTranslation: 190),
      .compact)
  }

  func testDetailAndAccessibilityLayoutsKeepTheirOwnBounds() {
    let detail = FindPanelLayout(
      viewportHeight: 800, bottomInset: 34, showsDetail: true, usesAccessibilitySize: false)
    XCTAssertEqual(detail.height(for: .compact), 151)
    XCTAssertEqual(detail.height(for: .medium), 450)

    let accessible = FindPanelLayout(
      viewportHeight: 800, bottomInset: 34, showsDetail: false, usesAccessibilitySize: true)
    for detent in FindPanelDetent.allCases {
      XCTAssertEqual(accessible.height(for: detent), 806)
    }
    XCTAssertEqual(accessible.height(startingAt: 806, translation: 500), 806)
  }

  func testShortViewportNeverProducesAnInvertedHeightRange() {
    let short = FindPanelLayout(
      viewportHeight: 100, bottomInset: 0, showsDetail: true, usesAccessibilitySize: false)
    for detent in FindPanelDetent.allCases {
      XCTAssertEqual(short.height(for: detent), 72)
    }
    XCTAssertEqual(short.height(startingAt: 450, translation: -200), 72)
  }
}
