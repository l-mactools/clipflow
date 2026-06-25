import AppKit
import SwiftUI

struct QuickPanelView: View {
    @ObservedObject var controller: QuickPanelController
    @ObservedObject var store: ClipboardStore

    private var items: [ClipboardItem] {
        controller.visibleItems
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
                Text("输入搜索   ⌘1-⌘9 直选   ⌘↩ 粘贴")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                QuickSearchField(
                    text: $controller.query,
                    placeholder: "输入即可搜索最近记录",
                    onMoveUp: { controller.moveSelection(by: -1) },
                    onMoveDown: { controller.moveSelection(by: 1) },
                    onSubmit: { commandPressed in
                        controller.confirmSelection(pasteAfterCopy: commandPressed)
                    },
                    onCancel: { controller.dismiss() }
                )
                .frame(height: 22)
                if !controller.query.isEmpty {
                    Button {
                        controller.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                Group {
                    if items.isEmpty {
                        ContentUnavailableView(
                            controller.query.isEmpty ? "暂无剪贴板历史" : "没有匹配记录",
                            systemImage: "clipboard",
                            description: Text("继续复制内容，拾笺会自动记录可取回的片段")
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    row(item, index: index)
                                        .id(index)
                                }
                            }
                            .padding(10)
                        }
                    }
                }
                .onChange(of: controller.selectedIndex) { _, index in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
                .onChange(of: controller.query) { _, _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(0, anchor: .top)
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

/// 原生 NSTextField 封装：使用系统文本输入路径，因而完整支持中文/日文等输入法（IME）。
/// 方向键、回车、Esc 由 delegate 的 doCommandBySelector 处理——输入法组合（marked text）
/// 进行时这些按键会先交给输入法，不会触发导航，从而保证候选词的选择与确认正常。
struct QuickSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onSubmit: (Bool) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if !context.coordinator.didInitialFocus {
            context.coordinator.didInitialFocus = true
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickSearchField
        var didInitialFocus = false

        init(_ parent: QuickSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                let commandPressed = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
                parent.onSubmit(commandPressed)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
