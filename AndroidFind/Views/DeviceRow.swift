import SwiftUI

struct DeviceRow: View {
  let device: FindDevice
  var isPlaying = false
  var lookupStatus: String?

  var body: some View {
    HStack(spacing: 12) {
      DeviceArtwork(device: device, size: 30)
        .frame(width: 44, height: 44)
        .background(FindMyStyle.deviceImageBackground, in: Circle())
        .overlay(
          Circle()
            .stroke(.gray.opacity(0.1), lineWidth: 0.5))
      VStack(alignment: .leading, spacing: 3) {
        Text(device.name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
        if let place = device.place {
          TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(place + " · " + device.activityText(at: context.date))
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        } else {
          Text(
            device.coordinate == nil
              ? (lookupStatus ?? device.connectionStatus ?? "位置情報を取得していません") : device.activityText()
          )
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .lineLimit(2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if lookupStatus == "位置情報を取得中…" {
        ProgressView()
          .controlSize(.mini)
          .accessibilityLabel("位置情報を取得中")
      }
      if isPlaying {
        Image(systemName: "speaker.wave.2.fill")
          .foregroundStyle(FindMyStyle.sound)
          .accessibilityLabel("サウンドを再生中")
      }
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 13)
    .contentShape(Rectangle())
  }
}
