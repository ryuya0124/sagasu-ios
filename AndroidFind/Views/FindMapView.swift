import MapKit
import SwiftUI

struct FindMapView: View {
  @Binding var camera: MapCameraPosition
  @Binding var mapSelection: String?
  let devices: [FindDevice]
  let selectedID: String?
  let satellite: Bool
  let mapScope: Namespace.ID
  let onSelect: (FindDevice) -> Void
  let onCameraChange: (MapCamera) -> Void

  var body: some View {
    Map(position: $camera, selection: $mapSelection, scope: mapScope) {
      ForEach(devices) { device in
        if let coordinate = device.coordinate {
          Annotation(device.name, coordinate: coordinate, anchor: .bottom) {
            DeviceMapPin(device: device, isSelected: selectedID == device.id)
              .onTapGesture { onSelect(device) }
          }
          .annotationTitles(.hidden)
          .tag(device.id)
        }
      }
    }
    .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
    .mapControlVisibility(.hidden)
    .ignoresSafeArea()
    .accessibilityIdentifier("deviceMap")
    .onMapCameraChange(frequency: .onEnd) { context in onCameraChange(context.camera) }
  }

}
