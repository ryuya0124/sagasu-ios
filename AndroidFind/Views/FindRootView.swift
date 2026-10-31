import MapKit
import SwiftUI

/// Coordinates map selection and sheets; drawing and drag handling live in their own views.
struct FindRootView: View {
  @Bindable var store: FindStore
  @State private var tab: FindTab = .devices
  @State private var camera: MapCameraPosition = .region(
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: 35.6814, longitude: 139.7671),
      span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
  @State private var detent: FindPanelDetent = .medium
  @State private var search = ""
  @State private var isSearching = false
  @State private var mapSelection: String?
  @State private var visibleCamera: MapCamera?
  @AppStorage("satelliteMap") private var satellite = false
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Namespace private var mapScope

  private var expanded: Bool { detent == .expanded }
  private var isShowingDetail: Bool { tab == .devices && store.selectedDevice != nil }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .bottom) {
        if !store.showGoogle {
          GoogleWebView(session: store.google)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        map
          .overlay(alignment: .topTrailing) { mapControls }
          .overlay(alignment: .topLeading) { if store.isDemo { demoPill } }
        panel(in: geometry)
          .padding(.horizontal, FindMyStyle.panelInset)
          .padding(.bottom, FindMyStyle.panelBottomInset - geometry.safeAreaInsets.bottom)
      }
    }
    .onChange(of: store.showGoogle, initial: true) { _, presented in
      store.googleBrowserPresented(presented)
    }
    .sheet(isPresented: $store.showGoogle, onDismiss: { store.googleDidDismiss() }) {
      GoogleConnectionView(
        session: store.google, action: store.googleAction, actionMessage: store.googleActionMessage
      )
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $store.showAccount, onDismiss: { store.accountDidDismiss() }) {
      AccountView(store: store)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(
          .visible)
    }
    .alert(
      "探す",
      isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    ) {
      Button("OK", role: .cancel) { store.notice = nil }
    } message: {
      Text(store.notice ?? "")
    }
    .onChange(of: store.selectedID) { _, id in
      if id != nil {
        withAnimation(.spring(duration: 0.35)) {
          tab = .devices
          detent = .medium
          isSearching = false
          search = ""
        }
      }
      focusSelected()
    }
    .onChange(of: store.selectedDevice?.latitude) { _, _ in focusSelected() }
    .onChange(of: store.selectedDevice?.longitude) { _, _ in focusSelected() }
    .onChange(of: store.devices.map { [$0.latitude, $0.longitude] }) { _, _ in
      if store.selectedDevice == nil, !camera.positionedByUser { fitAll() }
    }
    .onChange(of: store.devices.count) { _, _ in
      if store.selectedDevice != nil { focusSelected() } else { fitAll() }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { store.resume() } else { store.pauseLocationPrefetch() }
    }
    .onChange(of: detent) { _, value in
      if value != .expanded {
        isSearching = false
        search = ""
      }
      if store.selectedDevice != nil { focusSelected() }
    }
    .onChange(of: mapSelection) { _, id in
      if let device = store.devices.first(where: { $0.id == id }) { store.select(device) }
    }
    .sensoryFeedback(.selection, trigger: store.selectedID)
    .task {
      if store.selectedDevice != nil { focusSelected() } else { fitAll() }
      store.start()
    }
  }

  private var map: some View {
    FindMapView(
      camera: $camera,
      mapSelection: $mapSelection,
      devices: store.devices,
      selectedID: store.selectedID,
      satellite: satellite,
      mapScope: mapScope,
      onSelect: { store.select($0) },
      onCameraChange: { visibleCamera = $0 })
  }

  private var mapControls: some View {
    FindMapControls(
      satellite: $satellite,
      mapScope: mapScope,
      hasSelectedDevice: store.selectedDevice != nil,
      hasPerspective: (visibleCamera?.pitch ?? 0) > 10,
      onLocate: {
        if store.selectedDevice != nil { focusSelected() } else { fitAll() }
      },
      onTogglePerspective: togglePerspective)
  }

  private func togglePerspective() {
    var target =
      visibleCamera
      ?? MapCamera(
        centerCoordinate: store.selectedDevice?.coordinate
          ?? CLLocationCoordinate2D(latitude: 35.6814, longitude: 139.7671),
        distance: 1200)
    target.pitch = target.pitch > 10 ? 0 : 55
    withAnimation(.easeInOut(duration: 0.55)) { camera = .camera(target) }
  }

  private var demoPill: some View {
    Button {
      store.showAccount = true
    } label: {
      Label("デモ", systemImage: "eye")
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .findMyGlass(in: Capsule())
    }
    .buttonStyle(.plain)
    .padding(.leading, 16)
    .padding(.top, 12)
    .accessibilityIdentifier(
      "demoBadge")
  }

  private func panel(in geometry: GeometryProxy) -> some View {
    let layout = FindPanelLayout(
      viewportHeight: geometry.size.height,
      bottomInset: geometry.safeAreaInsets.bottom,
      showsDetail: isShowingDetail,
      usesAccessibilitySize: dynamicTypeSize.isAccessibilitySize)

    return FindPanel(detent: $detent, layout: layout) {
      if isShowingDetail, let device = store.selectedDevice {
        DeviceDetailView(store: store, device: device)
      } else {
        Group {
          if tab == .devices {
            DeviceListView(
              store: store,
              search: $search,
              isSearching: $isSearching,
              showsContent: detent != .compact || dynamicTypeSize.isAccessibilitySize,
              onBeginSearch: {
                withAnimation {
                  detent = .expanded
                  isSearching = true
                }
              })
          } else {
            FindSecondaryPanel(store: store, tab: tab)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        FindTabBar(selection: tab, onSelect: selectTab)
          .padding(.bottom, max(geometry.safeAreaInsets.bottom - FindMyStyle.panelBottomInset, 12))
      }
    }
  }

  private func selectTab(_ selection: FindTab) {
    withAnimation(.easeOut(duration: 0.24)) {
      tab = selection
      detent = .medium
      isSearching = false
      search = ""
    }
  }

  private func focusSelected() {
    guard let coordinate = store.selectedDevice?.coordinate else { return }
    withAnimation(.easeInOut(duration: 0.55)) {
      camera = .region(
        MKCoordinateRegion(
          center: CLLocationCoordinate2D(
            latitude: coordinate.latitude - (expanded ? 0.0041 : 0.0035),
            longitude: coordinate.longitude),
          span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }
  }

  private func fitAll() {
    let coordinates = store.devices.compactMap(\.coordinate)
    guard !coordinates.isEmpty else { return }
    var rect = MKMapRect.null
    for coordinate in coordinates {
      let point = MKMapPoint(coordinate)
      rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
    }
    let padding = max(rect.size.width * 0.6, 700)
    withAnimation(.easeInOut(duration: 0.5)) {
      camera = .rect(
        rect.insetBy(dx: -padding, dy: -padding * 1.8)
          .offsetBy(dx: 0, dy: padding * 0.6))
    }
  }
}
