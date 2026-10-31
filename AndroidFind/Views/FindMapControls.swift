import MapKit
import SwiftUI

struct FindMapControls: View {
  @Binding var satellite: Bool
  let mapScope: Namespace.ID
  let hasSelectedDevice: Bool
  let hasPerspective: Bool
  let onLocate: () -> Void
  let onTogglePerspective: () -> Void
  @State private var showMapOptions = false

  var body: some View {
    VStack(spacing: 10) {
      VStack(spacing: 0) {
        Button {
          showMapOptions = true
        } label: {
          Image(systemName: "map.fill")
            .font(.system(size: 20))
            .frame(width: 44, height: 44)
        }
        .accessibilityLabel("地図の表示")
        .accessibilityValue(satellite ? "航空写真" : "標準")
        .accessibilityIdentifier("mapDisplayOptions")
        .popover(isPresented: $showMapOptions) {
          VStack(alignment: .leading, spacing: 18) {
            Text("地図の表示")
              .font(.headline)
            VStack(spacing: 0) {
              mapStyleOption("標準", symbol: "map", isSatellite: false)
              Divider()
                .padding(.leading, 40)
              mapStyleOption("航空写真", symbol: "globe.americas.fill", isSatellite: true)
            }
          }
          .padding(20)
          .frame(width: 260)
          .presentationCompactAdaptation(.popover)
        }
        Divider()
          .frame(width: 27)
          .opacity(0.5)
        Button {
          onLocate()
        } label: {
          Image(systemName: "location")
            .font(.system(size: 22, weight: .medium))
            .frame(
              width: 44, height: 44)
        }
        .accessibilityLabel(!hasSelectedDevice ? "すべてのデバイスを表示" : "選択したデバイスを中央に表示")
      }
      .buttonStyle(.plain)
      .findMyGlass(in: Capsule())
      Button {
        onTogglePerspective()
      } label: {
        Text(hasPerspective ? "2D" : "3D")
          .font(.system(size: 17, weight: .medium))
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .findMyGlass(in: Circle())
      .accessibilityLabel("地図の2D・3D切り替え")
      MapCompass(scope: mapScope)
        .mapControlVisibility(.visible)
        .frame(width: 44, height: 44)
        .findMyGlass(in: Circle())
    }
    .foregroundStyle(.primary)
    .tint(.primary)
    .padding(.trailing, 16)
    .padding(.top, 12)
  }

  private func mapStyleOption(_ title: String, symbol: String, isSatellite: Bool) -> some View {
    Button {
      satellite = isSatellite
      showMapOptions = false
    } label: {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.title3)
          .frame(width: 26)
        Text(title)
          .font(.body)
        Spacer()
        if satellite == isSatellite {
          Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(.blue)
        }
      }
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(satellite == isSatellite ? [.isSelected] : [])
    .accessibilityIdentifier(isSatellite ? "satelliteMapOption" : "standardMapOption")
  }

}
