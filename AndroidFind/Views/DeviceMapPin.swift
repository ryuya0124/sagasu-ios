import SwiftUI

struct DeviceMapPin: View {
  let device: FindDevice
  let isSelected: Bool

  var body: some View {
    VStack(spacing: 3) {
      ZStack(alignment: .top) {
        if isSelected {
          FindMyMarkerShape()
            .fill(FindMyStyle.mapMarkerBackground)
            .frame(width: 64, height: 73)
        } else {
          Circle()
            .fill(FindMyStyle.mapMarkerBackground)
            .frame(width: 38, height: 38)
        }
        DeviceArtwork(device: device, size: isSelected ? 44 : 28)
          .frame(width: isSelected ? 64 : 38, height: isSelected ? 64 : 38)
      }
      .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
      if isSelected {
        Circle()
          .fill(FindMyStyle.mapMarkerBackground)
          .frame(width: 5, height: 5)
          .overlay(
            Circle()
              .stroke(.gray.opacity(0.25), lineWidth: 0.5))
      }
    }
    .accessibilityLabel(device.name)
  }
}

private struct FindMyMarkerShape: Shape {
  func path(in rect: CGRect) -> Path {
    let diameter = rect.width
    var path = Path(ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter))
    path.move(to: CGPoint(x: diameter * 0.63, y: diameter * 0.91))
    path.addQuadCurve(
      to: CGPoint(x: diameter * 0.5, y: rect.maxY),
      control: CGPoint(x: diameter * 0.56, y: diameter * 0.97))
    path.addQuadCurve(
      to: CGPoint(x: diameter * 0.37, y: diameter * 0.91),
      control: CGPoint(x: diameter * 0.44, y: diameter * 0.97))
    path.closeSubpath()
    return path
  }
}
