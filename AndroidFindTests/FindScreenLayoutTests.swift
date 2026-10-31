import XCTest

@testable import AndroidFind

final class FindScreenLayoutTests: XCTestCase {
  func testPhoneAndDuoCoverKeepTheBottomPanelWithinTheScreen() {
    let phone = FindScreenLayout(width: 402, height: 874)
    XCTAssertFalse(phone.isSidebar)
    XCTAssertEqual(phone.panelWidth, 382)
    let cover = FindScreenLayout(width: 466, height: 678)
    XCTAssertFalse(cover.isSidebar)
    XCTAssertEqual(cover.panelWidth, 446)
  }

  func testOpenDuoAndIPadUseALeftPanelInsteadOfAFullWidthSheet() {
    for size in [(951.0, 669.0), (1032.0, 1376.0), (1376.0, 1032.0)] {
      let layout = FindScreenLayout(width: size.0, height: size.1)
      XCTAssertTrue(layout.isSidebar)
      XCTAssertEqual(layout.panelWidth, 380)
      XCTAssertLessThan(layout.panelWidth, size.0 / 2)
    }
  }

  func testNarrowIPadSplitAndShortLandscapeWindowRemainUsable() {
    let split = FindScreenLayout(width: 507, height: 1032)
    XCTAssertFalse(split.isSidebar)
    XCTAssertEqual(split.panelWidth, 487)
    XCTAssertFalse(FindScreenLayout(width: 874, height: 320).isSidebar)
    XCTAssertEqual(FindScreenLayout(width: 0, height: 0).panelWidth, 0)
  }

  func testSidebarKeepsResizableDetentsAndAdaptsTheirHeightsToTheWindow() {
    let layout = FindPanelLayout(
      viewportHeight: 669, bottomInset: 0, showsDetail: false,
      usesAccessibilitySize: false, isSidebar: true)
    XCTAssertEqual(layout.height(for: .compact), 160)
    XCTAssertEqual(layout.height(for: .medium), 520)
    XCTAssertEqual(layout.height(for: .expanded), 589)
    let phone = FindPanelLayout(
      viewportHeight: 678, bottomInset: 34, showsDetail: false, usesAccessibilitySize: false)
    XCTAssertEqual(phone.height(for: .medium), 410)
  }

  func testAccessibilityTextCanUseAWiderSidebarWithoutCoveringTheWholeMap() {
    let layout = FindScreenLayout(width: 951, height: 669, usesAccessibilitySize: true)
    XCTAssertEqual(layout.panelWidth, 440)
    XCTAssertLessThan(layout.panelWidth, 951 / 2)
  }

  func testVerticalTabsLeaveRoomForTheDuoSystemBarOnTheCover() {
    let cover = FindScreenLayout(width: 466, height: 678, usesVerticalTabs: true)
    XCTAssertFalse(cover.isSidebar)
    XCTAssertEqual(cover.panelWidth + cover.tabRailWidth + cover.panelInset * 2, 466)
    let open = FindScreenLayout(width: 951, height: 669, usesVerticalTabs: true)
    XCTAssertTrue(open.isSidebar)
    XCTAssertEqual(open.panelWidth, 380)
  }
}
