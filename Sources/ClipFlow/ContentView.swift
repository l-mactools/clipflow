import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ClipboardStore
    @Environment(\.openSettings) private var openSettings
    @State private var selectedID: ClipboardItem.ID?
    @State private var showingBasket = false
    @State private var basketMergeFormat: BasketMergeFormat = .plainText

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if showingBasket {
                BasketView(selectedFormat: $basketMergeFormat)
            } else {
                history
            }
        } detail: {
            if showingBasket {
                basketPreview
            } else {
                detail
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(nsImage: Brand.icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("拾笺").font(.headline)
                    Text("本地剪贴板").font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 6) {
                filterButton(title: "全部内容", symbol: "tray.full", kind: nil)
                ForEach(ClipKind.allCases) { kind in
                    filterButton(title: kind.rawValue, symbol: kind.symbol, kind: kind)
                }

                Divider().padding(.vertical, 4)

                Button {
                    showingBasket = true
                    store.selectedKind = nil
                } label: {
                    HStack {
                        Image(systemName: "archivebox").frame(width: 20)
                        Text("篮子")
                        Spacer()
                        if store.basket.count > 0 {
                            Text("\(store.basket.count)")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        showingBasket ? Color.accentColor.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack {
                Circle()
                    .fill(store.isMonitoring ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(store.isMonitoring ? "正在监听" : "监听已暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
    }

    private func filterButton(title: String, symbol: String, kind: ClipKind?) -> some View {
        Button {
            showingBasket = false
            store.selectedKind = kind
        } label: {
            HStack {
                Image(systemName: symbol).frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(!showingBasket && store.selectedKind == kind ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var history: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索剪贴板历史…", text: $store.searchText)
                    .textFieldStyle(.plain)
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .padding(14)

            if store.filteredItems.isEmpty {
                ContentUnavailableView(
                    store.searchText.isEmpty ? "复制一些内容试试" : "没有匹配内容",
                    systemImage: "clipboard",
                    description: Text("拾笺会在本机保存最近的复制记录")
                )
            } else {
                List(store.filteredItems, selection: $selectedID) { item in
                    ClipRow(item: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("复制") { store.copy(item) }
                            Button(item.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(item) }
                            Divider()
                            Button("删除", role: .destructive) { store.delete(item) }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 390)
        .toolbar {
            ToolbarItem {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    openSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSRunningApplication.current.activate(options: [.activateAllWindows])
                        let settingsWindow = NSApp.windows.first(where: {
                            ($0.title.localizedCaseInsensitiveContains("settings") ||
                             $0.title.localizedCaseInsensitiveContains("设置")) &&
                            $0.canBecomeKey
                        })
                        settingsWindow?.makeKeyAndOrderFront(nil)
                        settingsWindow?.orderFrontRegardless()
                    }
                } label: {
                    Label("快捷键设置", systemImage: "keyboard")
                }
            }
            ToolbarItem {
                Button("清理", systemImage: "trash") { store.clearUnpinned() }
            }
        }
    }

    @ViewBuilder private var basketPreview: some View {
        if store.basket.isEmpty {
            ContentUnavailableView("篮子是空的", systemImage: "archivebox")
        } else {
            let previewText = store.mergedBasketText(format: basketMergeFormat)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(basketMergeFormat.rawValue, systemImage: "eye")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                    Text("\(store.basket.filter { $0.snapshot.kind != .image }.count) 条文本")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Divider()
                ScrollView {
                    Text(previewText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder private var detail: some View {
        if let selectedID, let item = store.items.first(where: { $0.id == selectedID }) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label(item.kind.rawValue, systemImage: item.kind.symbol)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { store.toggleFavorite(item) } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                    }
                    Button("复制", systemImage: "doc.on.doc") { store.copy(item) }
                        .buttonStyle(.borderedProminent)
                }
                ScrollView {
                    if item.kind == .image, let image = store.image(for: item) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 520)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text(item.text)
                            .font(.system(.body, design: item.kind == .text ? .monospaced : .default))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(item.createdAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
        } else {
            ContentUnavailableView("选择一条记录", systemImage: "cursorarrow.click.2")
        }
    }
}

private struct ClipRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.indigo)
                .frame(width: 34, height: 34)
                .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).lineLimit(2)
                Text(item.createdAt, style: .relative)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
        }
        .padding(.vertical, 5)
    }
}

private struct BasketView: View {
    @EnvironmentObject private var store: ClipboardStore
    @Binding var selectedFormat: BasketMergeFormat
    @State private var copyConfirmed = false
    @State private var showingClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("格式", selection: $selectedFormat) {
                    ForEach(BasketMergeFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 160)

                Spacer()

                Button {
                    store.copyMergedBasket(format: selectedFormat)
                    copyConfirmed = true
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        copyConfirmed = false
                    }
                } label: {
                    Label(copyConfirmed ? "已复制 ✓" : "合并取用",
                          systemImage: copyConfirmed ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.basket.isEmpty)

                Button("清空未固定", systemImage: "trash") {
                    showingClearConfirm = true
                }
                .disabled(store.basket.filter { !$0.isPinned }.isEmpty)
            }
            .padding(14)

            Divider()

            if store.basket.isEmpty {
                ContentUnavailableView(
                    "篮子是空的",
                    systemImage: "archivebox",
                    description: Text("在快捷面板中按 ⇥ 将条目加入篮子")
                )
            } else {
                List {
                    ForEach(store.basket) { entry in
                        BasketRow(entry: entry)
                    }
                    .onMove { source, destination in
                        store.moveBasket(from: source, to: destination)
                    }
                }
                .listStyle(.inset)

                Divider()
                Text("合并取用将内容写入剪贴板，再 ⌘V 粘贴到目标位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .navigationSplitViewColumnWidth(min: 320, ideal: 480)
        .alert("清空篮子中未固定的条目？", isPresented: $showingClearConfirm) {
            Button("清空", role: .destructive) { store.clearBasket() }
            Button("取消", role: .cancel) {}
        }
    }
}

private struct BasketRow: View {
    @EnvironmentObject private var store: ClipboardStore
    let entry: BasketEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.snapshot.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.indigo)
                .frame(width: 34, height: 34)
                .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.snapshot.title).lineLimit(2)
                Text(entry.addedAt, style: .relative)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.toggleBasketPin(entry)
            } label: {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(entry.isPinned ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)

            Button {
                store.removeFromBasket(entry)
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 5)
    }
}
