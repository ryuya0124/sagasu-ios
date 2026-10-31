import SwiftUI

struct FindTabBar: View {
  let selection: FindTab
  let onSelect: (FindTab) -> Void

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .opacity(0.65)
      HStack(spacing: 0) {
        ForEach(FindTab.allCases, id: \.self) { item in
          Button {
            onSelect(item)
          } label: {
            VStack(spacing: 4) {
              tabIcon(for: item)
                .frame(height: 25)
              Text(item.rawValue)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .foregroundStyle(selection == item ? Color.findAccent : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selection == item ? .isSelected : [])
          .accessibilityIdentifier("tab-\(item.rawValue)")
        }
      }
      .padding(.horizontal, 9)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("findMyTabBar")
  }

  @ViewBuilder
  private func tabIcon(for item: FindTab) -> some View {
    Image(systemName: item.symbol)
      .font(.system(size: 22, weight: .regular))
  }

}
