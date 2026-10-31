import SwiftUI
import UIKit

@MainActor
final class AuthenticationPresenter {
  weak var window: UIWindow?

  func current() -> UIViewController? {
    // Use the window containing the tapped button, not another active iPad/Duo scene.
    guard var controller = window?.rootViewController else { return nil }
    while let presented = controller.presentedViewController, !presented.isBeingDismissed {
      controller = presented
    }
    return controller
  }
}

struct AuthenticationPresentationAnchor: UIViewRepresentable {
  let presenter: AuthenticationPresenter

  func makeUIView(context: Context) -> AnchorView {
    AnchorView(presenter: presenter)
  }

  func updateUIView(_ view: AnchorView, context: Context) {}

  final class AnchorView: UIView {
    private weak var presenter: AuthenticationPresenter?

    init(presenter: AuthenticationPresenter) {
      self.presenter = presenter
      super.init(frame: .zero)
      isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      presenter?.window = window
    }
  }
}
