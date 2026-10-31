import SwiftUI

/// A compact vertical counterpart to the phone's bottom tabs for the system's bar edge.
struct FindTabRail: View {
  let selection: FindTab
  let onSelect: (FindTab) -> Void

  var body: some View {
    VStack(spacing: 8) {
      ForEach(FindTab.allCases, id: \.self) { item in
        Button {
          onSelect(item)
        } label: {
          Image(systemName: item.symbol)
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(selection == item ? Color.findAccent : .primary)
            .frame(width: 44, height: 44)
            .background(
              selection == item ? Color.findAccent.opacity(0.12) : .clear,
              in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selection == item ? [.isSelected] : [])
        .accessibilityIdentifier("tab-\(item.rawValue)")
      }
    }
    .padding(8)
    .findMyGlass(in: Capsule())
    .accessibilityElement(children: .contain)
  }
}
