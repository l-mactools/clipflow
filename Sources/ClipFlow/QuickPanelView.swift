import SwiftUI

struct QuickPanelView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var store: ClipboardStore

    private var items: [ClipboardItem] {
        Array(store.recentItems.prefix(10))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clipboard")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.indigo)
                Text("剪贴板历史")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("↑↓ 选择   ↩ 确认   esc 取消")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: controller.selectedIndex) { _, index in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 640, height: 460)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ item: ClipboardItem, index: Int) -> some View {
        HStack(spacing: 12) {
            itemPreview(item, selected: controller.selectedIndex == index)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .opacity(0.7)
            }
            if index < 9 {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .opacity(0.6)
            }
        }
        .foregroundStyle(controller.selectedIndex == index ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            controller.selectedIndex == index ? Color.indigo.gradient : Color.clear.gradient,
            in: RoundedRectangle(cornerRadius: 11)
        )
        .contentShape(Rectangle())
        .onTapGesture { controller.select(index) }
        .onTapGesture(count: 2) {
            controller.select(index)
            controller.confirmSelection()
        }
    }

    @ViewBuilder
    private func itemPreview(_ item: ClipboardItem, selected: Bool) -> some View {
        if item.kind == .image, let image = store.image(for: item) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(selected ? .white : .indigo)
                .frame(width: 32, height: 32)
                .background(
                    selected ? Color.white.opacity(0.18) : Color.indigo.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
    }
}
