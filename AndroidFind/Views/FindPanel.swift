import SwiftUI

/// The drawer owns its drag state; the list and its ScrollView keep their own gestures.
struct FindPanel<Content: View>: View {
  @Binding var detent: FindPanelDetent
  let layout: FindPanelLayout
  @ViewBuilder let content: Content

  @GestureState private var isDragging = false
  @State private var drag: DragPosition?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private struct DragPosition {
    let startHeight: CGFloat
    let translation: CGFloat
  }

  private var currentHeight: CGFloat {
    guard let drag else { return layout.height(for: detent) }
    return layout.height(startingAt: drag.startHeight, translation: drag.translation)
  }

  private var settlingAnimation: Animation? {
    reduceMotion ? nil : .easeOut(duration: 0.24)
  }

  var body: some View {
    VStack(spacing: 0) {
      grabber
      content
    }
    .frame(height: currentHeight, alignment: .top)
    .clipShape(RoundedRectangle(cornerRadius: FindMyStyle.panelRadius, style: .continuous))
    .findMyGlass(in: RoundedRectangle(cornerRadius: FindMyStyle.panelRadius, style: .continuous))
    .shadow(color: .black.opacity(0.08), radius: 12, y: 3)
    .onChange(of: isDragging) { _, active in
      // onEnded is not called when the system cancels a gesture (for example, on interruption).
      if !active, drag != nil {
        withAnimation(settlingAnimation) { drag = nil }
      }
    }
    .onChange(of: layout) { _, _ in
      // An orientation, text-size or detail change invalidates the captured drag bounds.
      drag = nil
    }
  }

  private var grabber: some View {
    Capsule()
      .fill(.secondary.opacity(0.4))
      .frame(width: 46, height: 5)
      .padding(.top, 7)
      .padding(.bottom, 14)
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(settlingAnimation) {
          detent = detent == .expanded ? .medium : .expanded
        }
      }
      .gesture(dragGesture)
      .accessibilityIdentifier("panelGrabber")
      .accessibilityLabel(detent == .expanded ? "パネルを縮小" : "パネルを拡大")
      .accessibilityValue(detent.accessibilityDescription)
      .accessibilityAddTraits(.isButton)
      .accessibilityAdjustableAction { direction in
        withAnimation(settlingAnimation) {
          detent = direction == .increment ? .expanded : .compact
        }
      }
  }

  private var dragGesture: some Gesture {
    // The grabber moves as the panel grows. Local coordinates would feed that movement
    // back into translation, making the panel oscillate under a stationary finger.
    DragGesture(minimumDistance: 8, coordinateSpace: .global)
      .updating($isDragging) { _, active, transaction in
        transaction.animation = nil
        active = true
      }
      .onChanged { value in
        let startHeight = drag?.startHeight ?? layout.height(for: detent)
        withTransaction(Transaction(animation: nil)) {
          drag = DragPosition(startHeight: startHeight, translation: value.translation.height)
        }
      }
      .onEnded { value in
        let target = layout.destination(
          startingAt: drag?.startHeight ?? layout.height(for: detent),
          translation: value.translation.height,
          predictedTranslation: value.predictedEndTranslation.height)

        // Commit the detent and clear the temporary height together, with one animation.
        withAnimation(settlingAnimation) {
          detent = target
          drag = nil
        }
      }
  }
}
