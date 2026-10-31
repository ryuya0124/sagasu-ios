import SwiftUI

/// Follow the system's bar edge on iPhone Duo instead of identifying the device by name.
struct FindSystemBarLayout<Content: View>: View {
  @ViewBuilder let content: (HorizontalEdge?) -> Content

  var body: some View {
    if #available(iOS 27.1, *) {
      ModernBarLayout(content: content)
    } else {
      content(nil)
    }
  }
}

@available(iOS 27.1, *)
private struct ModernBarLayout<Content: View>: View {
  @Environment(\.toolbarVerticalEdge) private var edge
  @ViewBuilder let content: (HorizontalEdge?) -> Content

  var body: some View {
    content(edge)
  }
}
