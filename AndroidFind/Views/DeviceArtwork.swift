import SwiftUI

struct DeviceArtwork: View {
  let device: FindDevice
  var size: CGFloat = 48
  @State private var image: UIImage?
  @State private var isLoading = false

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else if isLoading {
        ProgressView()
          .controlSize(.mini)
      } else {
        Image(systemName: "questionmark")
          .font(.system(size: max(10, size * 0.3), weight: .medium))
          .foregroundStyle(.tertiary)
      }
    }
    .frame(width: size, height: size)
    .task(id: device.imageURL) {
      image = nil
      guard let url = device.imageURL else {
        isLoading = false
        return
      }
      isLoading = true
      let data = await DeviceImageRepository.shared.data(for: url)
      guard !Task.isCancelled else { return }
      image = data.flatMap { UIImage(data: $0) }
      isLoading = false
    }
    .accessibilityHidden(true)
  }
}
