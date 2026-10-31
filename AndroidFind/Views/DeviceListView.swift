import SwiftUI

struct DeviceListView: View {
  @Bindable var store: FindStore
  @Binding var search: String
  @Binding var isSearching: Bool
  let showsContent: Bool
  let onBeginSearch: () -> Void
  @ScaledMetric(relativeTo: .title2) private var headerSize: CGFloat = 27

  private var filteredDevices: [FindDevice] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return query.isEmpty
      ? store.devices : store.devices.filter { $0.name.localizedStandardContains(query) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text("デバイスを探す")
          .font(.system(size: headerSize, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 0)
        Menu {
          Button("Googleでデバイスを確認", systemImage: "plus") { store.connect() }
          Button("デバイス一覧を更新", systemImage: "arrow.clockwise") { store.refresh() }
          Button("デバイスを検索", systemImage: "magnifyingglass") {
            onBeginSearch()
          }
          Button("アカウントと表示の設定", systemImage: "person.crop.circle") { store.showAccount = true }
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 23, weight: .regular))
            .frame(width: 40, height: 40)
            .background(.quaternary.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("追加とその他の操作")
        .accessibilityIdentifier("deviceActionsMenu")
      }
      .padding(.horizontal, 22)
      .padding(.bottom, 10)
      if showsContent {
        ConnectionBanner(store: store)
          .padding(.horizontal, 22)
        if isSearching {
          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)
            TextField("デバイスを検索", text: $search)
              .font(.body)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            if !search.isEmpty {
              Button {
                search = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .accessibilityLabel("検索をクリア")
            }
          }
          .padding(11)
          .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
          .padding(.horizontal, 22)
          .padding(.bottom, 10)
        }
        if store.devices.isEmpty {
          DeviceConnectionPrompt(store: store)
        } else {
          ScrollView {
            LazyVStack(spacing: 0) {
              if filteredDevices.isEmpty {
                Text("一致するデバイスがありません")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .padding(24)
              }
              ForEach(filteredDevices) { device in
                Button {
                  withAnimation(.spring(duration: 0.35)) { store.select(device) }
                } label: {
                  DeviceRow(
                    device: device, isPlaying: store.soundState(for: device.id) == .playing,
                    lookupStatus: store.locationLookupStatus(for: device.id))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("device-\(device.id)")
                if device.id != filteredDevices.last?.id {
                  Divider()
                    .padding(.leading, 78)
                    .padding(.trailing, 22)
                }
              }
            }
          }
          .scrollIndicators(.hidden)
          .scrollDismissesKeyboard(.interactively)
          .refreshable { await store.refreshInventory() }
        }
      }
      Spacer(minLength: 0)
    }
  }

}
