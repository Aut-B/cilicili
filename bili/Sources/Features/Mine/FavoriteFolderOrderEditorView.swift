import SwiftUI

/// 收藏夹内视频的拖拽排序页。
///
/// 排序只保存在本机（B 站不提供收藏夹内顺序的写入接口），因此这里直接编辑
/// `LibraryStore.favoriteFolderOrder` 中该收藏夹的 BV 序列。
///
/// 页面以 `viewModel` 里的完整条目为准，未加载到的视频在保存时按原顺序补到末尾，
/// 不会因为翻页未完成而丢失内容。
struct FavoriteFolderOrderEditorView: View {
    let folder: FavoriteFolder
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var libraryStore: LibraryStore

    @State private var orderedEntries: [AccountVideoEntry] = []
    @State private var isLoading = true
    @State private var exportText: String = ""
    @State private var importDraft: String = ""
    @State private var isShowingImporter = false
    @State private var transferNotice: String?

    var body: some View {
        List {
            Section {
                ForEach(orderedEntries) { entry in
                    LibraryVideoRow(item: entry, timestampTitle: "收藏时间")
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: moveEntries)
            } header: {
                Text("\(orderedEntries.count) 个视频")
            } footer: {
                Text("长按右侧手柄拖动排序。顺序会决定「播放全部」的播放次序，并保存在本机。")
            }

            Section {
                Button {
                    libraryStore.resetFavoriteFolderOrder(for: folder.id)
                    orderedEntries = baseEntries
                } label: {
                    Label("恢复 B 站原始顺序", systemImage: "arrow.uturn.backward")
                }
                .disabled(libraryStore.favoriteFolderOrder.orderedVideoIDs(for: folder.id).isEmpty)

                Button {
                    exportText = libraryStore.favoriteFolderOrderExportText()
                    isShowingImporter = true
                } label: {
                    Label("导出 / 导入顺序…", systemImage: "square.and.arrow.up.on.square")
                }
            } header: {
                Text("跨设备同步")
            } footer: {
                Text("B 站不保存收藏夹内的自定义顺序。把下面的内容复制到另一台设备，再从那里导入即可同步。")
            }
        }
        .environment(\.editMode, .constant(.active))
        .tint(libraryStore.appTintColor)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .navigationTitle("编辑排序")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $isShowingImporter) {
            transferSheet
        }
    }

    // MARK: - 数据

    private var baseEntries: [AccountVideoEntry] {
        libraryStore.favoriteFolderOrder.applyingOrder(
            to: viewModel.favoriteFolderEntries[folder.id] ?? [],
            folderID: folder.id
        )
    }

    private func load() async {
        isLoading = true
        // 排序针对整份收藏夹，未加载的分页先补齐，否则拖拽只能覆盖已加载部分。
        await viewModel.loadAllFavoriteFolderEntries(folder)
        orderedEntries = baseEntries
        isLoading = false
    }

    private func moveEntries(from offsets: IndexSet, to destination: Int) {
        orderedEntries.move(fromOffsets: offsets, toOffset: destination)
        commit()
    }

    private func commit() {
        libraryStore.setFavoriteFolderOrder(
            orderedEntries.map(\.id),
            for: folder.id
        )
    }

    // MARK: - 导出导入

    private var transferSheet: some View {
        NavigationStack {
            List {
                Section {
                    TextEditor(text: $importDraft)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 220)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("粘贴顺序数据")
                } footer: {
                    Text("在另一台设备上复制「导出」得到的内容，粘贴到这里，然后点导入。")
                }

                if let transferNotice {
                    Section {
                        Text(transferNotice)
                            .foregroundStyle(transferNotice.hasPrefix("导入成功") ? .green : .secondary)
                    }
                }
            }
            .navigationTitle("顺序数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { isShowingImporter = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入") { performImport() }
                        .disabled(importDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func performImport() {
        if libraryStore.importFavoriteFolderOrder(from: importDraft) {
            transferNotice = "导入成功，已按新顺序重排。"
            Task {
                await viewModel.loadAllFavoriteFolderEntries(folder)
                orderedEntries = baseEntries
            }
        } else {
            transferNotice = "导入失败：内容不是有效的顺序数据。"
        }
    }
}
