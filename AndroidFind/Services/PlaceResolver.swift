import MapKit

@MainActor
protocol PlaceResolving {
  func name(for coordinate: CLLocationCoordinate2D) async -> String?
}

@MainActor
struct PlaceResolver: PlaceResolving {
  func name(for coordinate: CLLocationCoordinate2D) async -> String? {
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    if #available(iOS 26.0, *) {
      guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
      request.preferredLocale = Locale(identifier: "ja_JP")
      guard let item = try? await request.mapItems.first, !Task.isCancelled else { return nil }
      return item.address?.shortAddress ?? item.addressRepresentations?.cityWithContext
    } else {
      return await legacyName(for: location)
    }
  }

  @available(iOS, introduced: 18.0, obsoleted: 26.0)
  private func legacyName(for location: CLLocation) async -> String? {
    guard
      let place = try? await CLGeocoder()
        .reverseGeocodeLocation(
          location, preferredLocale: Locale(identifier: "ja_JP")
        )
        .first, !Task.isCancelled
    else { return nil }
    let components = [place.locality, place.subLocality, place.thoroughfare]
      .compactMap { $0 }.filter { !$0.isEmpty }
    return components.isEmpty ? place.name : components.joined()
  }
}
