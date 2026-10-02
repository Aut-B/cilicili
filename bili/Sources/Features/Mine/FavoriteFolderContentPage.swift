import SwiftUI

struct FavoriteFolderContentPage: View {
    let folder: FavoriteFolder
    @ObservedObject var viewModel: MineViewModel
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.openVideoAction) private var openVideo

    @State private var isPreparingQueue = false
    @State private var queueErrorMessage: String?
    @State private var isShowingOrderEditor = false

    var body: some View {
        List {
            Section {
                content
            } header: {
                if let count = folder.mediaCount {
                    Text("\(count) 个内容")
                }
            }
        }
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await playAll() }
                    } label: {
                        Label("播放全部", systemImage: "play.circle")
                    }
                    .disabled(!canPlayAll || isPreparingQueue)

                    Picker(selection: playbackOrderBinding) {
                        ForEach(VideoListenPlaybackOrder.allCases) { order in
                            Label(order.title, systemImage: order.systemImage)
                                .tag(order)
                        }
                    } label: {
                        Label("播放方式", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Divider()

                    Button {
                        isShowingOrderEditor = true
                    } label: {
                        Label("编辑排序", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(items.isEmpty)

                    Button {
                        Task { await reload() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                } label: {
                    if isPreparingQueue {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .disabled(!sessionStore.isLoggedIn || state.isLoading)
            }
        }
        .navigationDestination(isPresented: $isShowingOrderEditor) {
            FavoriteFolderOrderEditorView(folder: folder, viewModel: viewModel)
        }
        .alert("无法播放全部", isPresented: isShowingQueueError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(queueErrorMessage ?? "请稍后再试。")
        }
        .task {
            await loadIfNeeded()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !sessionStore.isLoggedIn {
            LibraryEmptyRow(title: "登录后同步账号收藏", systemImage: "star")
        } else if items.isEmpty && state.isLoading {
            LibraryLoadingRow(title: "正在同步收藏夹")
        } else if items.isEmpty, case .failed(let message) = state {
            LibraryErrorRow(title: "收藏夹同步失败", message: message) {
                Task { await reload() }
            }
        } else if items.isEmpty {
            LibraryEmptyRow(title: "这个收藏夹还没有视频", systemImage: "folder")
        } else {
            ForEach(items) { item in
                VideoRouteLink(item.videoItem) {
                    LibraryVideoRow(item: item, timestampTitle: "收藏时间")
                }
                .task {
                    await viewModel.loadMoreFavoriteFolderIfNeeded(folder, current: item)
                }
            }

            if state.isLoading {
                LibraryLoadingRow(title: "正在同步收藏夹")
            } else if loadMoreState.isLoading {
                LibraryLoadingRow(title: "正在加载更多收藏")
            } else if case .failed(let message) = state {
                LibraryErrorRow(title: "收藏夹同步失败", message: message) {
                    Task { await reload() }
                }
            } else if case .failed(let message) = loadMoreState {
                LibraryErrorRow(title: "更多收藏加载失败", message: message) {
                    Task { await viewModel.loadMoreFavoriteFolder(folder) }
                }
            } else if hasMore {
                LibraryLoadMoreTriggerRow(title: "正在加载更多收藏") {
                    Task { await viewModel.loadMoreFavoriteFolder(folder) }
                }
            }
        }
    }

    /// 按本地自定义顺序重排后的条目；未设置顺序时即 B 站原始顺序。
    private var items: [AccountVideoEntry] {
        libraryStore.favoriteFolderOrder.applyingOrder(
            to: viewModel.favoriteFolderEntries[folder.id] ?? [],
            folderID: folder.id
        )
    }

    private var state: LoadingState {
        viewModel.favoriteFolderEntryStates[folder.id] ?? .idle
    }

    private var loadMoreState: LoadingState {
        viewModel.favoriteFolderLoadMoreStates[folder.id] ?? .idle
    }

    private var hasMore: Bool {
        viewModel.favoriteFolderHasMore[folder.id] == true
    }

    private var canPlayAll: Bool {
        sessionStore.isLoggedIn && !items.isEmpty
    }

    private var isShowingQueueError: Binding<Bool> {
        Binding(
            get: { queueErrorMessage != nil },
            set: { if !$0 { queueErrorMessage = nil } }
        )
    }

    private var playbackOrderBinding: Binding<VideoListenPlaybackOrder> {
        Binding(
            get: { libraryStore.videoListenPlaybackOrder },
            set: { libraryStore.setVideoListenPlaybackOrder($0) }
        )
    }

    private func loadIfNeeded() async {
        guard sessionStore.isLoggedIn, items.isEmpty, !state.isLoading else { return }
        await reload()
    }

    private func reload() async {
        await viewModel.refreshFavoriteFolder(folder)
    }

    /// 拉取整个收藏夹，按本地顺序建队，然后打开队首。
    ///
    /// 队列在跳转前就已备好，`VideoDetailViewModel` 初始化时接管，
    /// 因此进入详情页后播完一条会自动续播下一条。
    private func playAll() async {
        guard !isPreparingQueue else { return }
        isPreparingQueue = true
        defer { isPreparingQueue = false }

        await viewModel.loadAllFavoriteFolderEntries(folder)

        let entries = items.filter { $0.videoItem.cid != nil || $0.aid != nil }
        let videos = entries.map(\.videoItem)
        guard let seed = videos.first else {
            queueErrorMessage = "这个收藏夹里没有可播放的视频。"
            return
        }

        FavoriteFolderPlaybackSession.shared.stage(
            folderID: folder.id,
            seed: seed,
            videos: videos
        )
        openVideo(seed)
    }
}
