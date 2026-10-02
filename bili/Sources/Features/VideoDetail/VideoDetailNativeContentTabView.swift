import SwiftUI
import UIKit

struct VideoDetailNativeContentTabView<Content: View>: View {
    /// 滚动内容为切换器预留的高度，须与 `VideoDetailToolbarSegmentedPickerView.height`
    /// 及其上下留白保持一致，否则底部会多出一段空白。
    private let segmentedPickerHeight: CGFloat =
        VideoDetailToolbarSegmentedPickerView.height + 8
    @Environment(\.appThemeTintColor) private var appTintColor
    @Binding var selection: VideoDetailContentTab
    let layoutWidth: CGFloat
    let topInset: CGFloat
    var bottomInset: CGFloat = 0
    var scrollAdjustment: VideoDetailScrollAdjustment?
    let mountsSecondaryContent: Bool
    var hidesBottomToolbar = false
    var placesTopInsetInScrollContent = false
    var interactiveMinimumPlayerHeight = VideoDetailShellLayout.collapsedToolbarHeight
    var contentRevision: Int = 0
    var onOpenCommentComposer: (() -> Void)?
    var onRefreshComments: () -> Void = {}
    var onSelectionWillChange: ((VideoDetailContentTab) -> Void)? = nil
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    var onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)? = nil
    var summary: AnyView? = nil
    let content: (VideoDetailContentTab, Bool) -> Content

    var body: some View {
        Group {
            if placesTopInsetInScrollContent {
                tabContent
            } else {
                VStack(spacing: 0) {
                    Color.clear.frame(height: topInset).accessibilityHidden(true)
                    tabContent
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .bottom) { ios15BottomBar }
        .toolbar {
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Group {
                        if selection == .comments {
                            VideoDetailToolbarCommentRefreshButton(action: onRefreshComments)
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                        } else {
                            Color.clear
                                .frame(
                                    width: VideoDetailToolbarCommentComposerButton.size,
                                    height: VideoDetailToolbarCommentComposerButton.size
                                )
                        }
                    }
                    .animation(.smooth(duration: 0.22), value: selection)
                    .allowsHitTesting(selection == .comments)
                    .accessibilityHidden(selection != .comments)
                }
                .sharedBackgroundVisibility(selection == .comments ? .automatic : .hidden)
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    VideoDetailToolbarSegmentedPickerView(selection: toolbarSelection)
                        .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)
                }
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Group {
                        if selection == .comments, let onOpenCommentComposer {
                            VideoDetailToolbarCommentComposerButton(action: onOpenCommentComposer)
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                        } else {
                            Color.clear
                                .frame(
                                    width: VideoDetailToolbarCommentComposerButton.size,
                                    height: VideoDetailToolbarCommentComposerButton.size
                                )
                        }
                    }
                    .animation(.smooth(duration: 0.22), value: selection)
                    .allowsHitTesting(selection == .comments)
                    .accessibilityHidden(selection != .comments)
                }
                .sharedBackgroundVisibility(selection == .comments ? .automatic : .hidden)
                ToolbarSpacer(.flexible, placement: .bottomBar)
        }
        .toolbarBackground(.hidden, for: .bottomBar)
        .toolbarVisibility(hidesBottomToolbar ? .hidden : .visible, for: .bottomBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .tint(appTintColor)
    }

    /// iOS 15 回退底栏。
    ///
    /// `.toolbar` 的 bottomBar 在本工程（UIKit 外壳承载的 SwiftUI 内容）于 iOS 15 上不渲染，
    /// 「简介 / 评论」整条切换栏会消失，评论入口随之丢失。iOS 15 用显式浮层补一条等价底栏；
    /// iOS 16 及以上仍走系统 toolbar，不做任何改动。
    @ViewBuilder
    private var ios15BottomBar: some View {
        if #available(iOS 16.0, *) {
            EmptyView()
        } else if !hidesBottomToolbar {
            VideoDetailIOS15BottomToolbar(
                selection: toolbarSelection,
                onRefreshComments: onRefreshComments,
                onOpenCommentComposer: onOpenCommentComposer
            )
        }
    }

    private var tabContent: some View {
        ZStack {
            ForEach(VideoDetailContentTab.allCases) { tab in
                page(for: tab)
                    .opacity(selection == tab ? 1 : 0)
                    .allowsHitTesting(selection == tab)
                    .accessibilityHidden(selection != tab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.smooth(duration: 0.28), value: selection)
        .background(VideoDetailTheme.background)
    }

    private var toolbarSelection: Binding<VideoDetailContentTab> {
        Binding(
            get: { selection },
            set: { newSelection in
                guard newSelection != selection else { return }
                onSelectionWillChange?(newSelection)
                selection = newSelection
            }
        )
    }

    @ViewBuilder
    private func page(for tab: VideoDetailContentTab) -> some View {
        let pageContent = {
            content(
                tab,
                mountsSecondaryContent || (tab == .comments && selection == .comments)
            )
        }
        if placesTopInsetInScrollContent {
            VideoDetailInteractiveScrollingTabPage(
                tab: tab,
                scrollAdjustment: scrollAdjustment,
                onScrollOffsetChange: onScrollOffsetChange,
                onScrollPhaseChange: onScrollPhaseChange,
                summary: tab == .detail ? summary : nil,
                topInset: topInset,
                minimumPlayerHeight: interactiveMinimumPlayerHeight,
                contentRevision: contentRevision,
                contentMountsSecondaryContent: mountsSecondaryContent
                    || (tab == .comments && selection == .comments),
                bottomInset: bottomInset + segmentedPickerHeight + 16,
                content: pageContent
            )
        } else {
            VideoDetailScrollingTabPage(
                tab: tab,
                scrollAdjustment: scrollAdjustment,
                onScrollOffsetChange: onScrollOffsetChange,
                onScrollPhaseChange: onScrollPhaseChange,
                summary: tab == .detail ? summary : nil,
                topInset: 0,
                minimumPlayerHeight: 0,
                bottomInset: bottomInset + segmentedPickerHeight + 16,
                content: { _ in pageContent() }
            )
        }
    }
}

@MainActor
private struct VideoDetailInteractiveScrollingTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
    let summary: AnyView?
    let topInset: CGFloat
    let minimumPlayerHeight: CGFloat
    let contentRevision: Int
    let contentMountsSecondaryContent: Bool
    let bottomInset: CGFloat
    let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            VideoDetailInteractiveScrollHost(
                tab: tab,
                viewportHeight: proxy.size.height,
                scrollAdjustment: scrollAdjustment,
                onScrollOffsetChange: onScrollOffsetChange,
                onScrollPhaseChange: onScrollPhaseChange,
                summary: summary,
                topInset: topInset,
                minimumPlayerHeight: minimumPlayerHeight,
                contentRevision: contentRevision,
                contentMountsSecondaryContent: contentMountsSecondaryContent,
                bottomInset: bottomInset,
                content: content
            )
        }
    }
}

@MainActor
private struct VideoDetailInteractiveScrollHost<Content: View>: UIViewRepresentable {
    let tab: VideoDetailContentTab
    let viewportHeight: CGFloat
    let scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
    let summary: AnyView?
    let topInset: CGFloat
    let minimumPlayerHeight: CGFloat
    let contentRevision: Int
    let contentMountsSecondaryContent: Bool
    let bottomInset: CGFloat
    let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = context.coordinator

        let hostingController = UIHostingController(rootView: scrollContent)
        hostingController.sizingOptions = .intrinsicContentSize
        hostingController.safeAreaRegions = []
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
        context.coordinator.hostingController = hostingController
        context.coordinator.update(
            scrollView: scrollView,
            tab: tab,
            scrollAdjustment: scrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange,
            onScrollPhaseChange: onScrollPhaseChange,
            bottomInset: bottomInset,
            contentConfiguration: contentConfiguration
        )
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let contentChanged = context.coordinator.contentConfiguration != contentConfiguration
        if contentChanged {
            context.coordinator.hostingController?.rootView = scrollContent
            context.coordinator.contentConfiguration = contentConfiguration
        }
        context.coordinator.update(
            scrollView: scrollView,
            tab: tab,
            scrollAdjustment: scrollAdjustment,
            onScrollOffsetChange: onScrollOffsetChange,
            onScrollPhaseChange: onScrollPhaseChange,
            bottomInset: bottomInset,
            contentConfiguration: contentConfiguration
        )
    }

    static func dismantleUIView(_ scrollView: UIScrollView, coordinator: Coordinator) {
        scrollView.delegate = nil
        coordinator.hostingController?.view.removeFromSuperview()
        coordinator.hostingController = nil
    }

    private var scrollContent: AnyView {
        return AnyView(
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topInset)
                    .accessibilityHidden(true)
                LazyVStack(spacing: 12) {
                    summary
                    content()
                }
                .padding(.top, 12)
            }
            .frame(
                minHeight: VideoDetailShellLayout.scrollContentMinimumHeight(
                    viewportHeight: viewportHeight,
                    expandedPlayerHeight: topInset,
                    minimumPlayerHeight: minimumPlayerHeight
                ),
                alignment: .top
            )
            .environment(
                \.videoDetailCommentsEmptyStateMinimumHeight,
                max(viewportHeight - bottomInset, 0)
            )
        )
    }

    private var contentConfiguration: ContentConfiguration {
        ContentConfiguration(
            viewportHeight: viewportHeight,
            topInset: topInset,
            minimumPlayerHeight: minimumPlayerHeight,
            contentRevision: contentRevision,
            contentMountsSecondaryContent: contentMountsSecondaryContent
        )
    }

    fileprivate struct ContentConfiguration: Equatable {
        let viewportHeight: CGFloat
        let topInset: CGFloat
        let minimumPlayerHeight: CGFloat
        let contentRevision: Int
        let contentMountsSecondaryContent: Bool
    }

    /// 详情页滚动宿主的中继对象。
    ///
    /// `@_optimize(none)`：Xcode 26 的 SIL 优化器在处理本类自动合成的
    /// `deinit`（符号后缀 `CfD`）时，`EarlyPerfInliner` pass 会段错误，导致整包
    /// `-O` 构建失败并回退到不优化的 `-Onone`（A9 机型上明显卡顿）。
    /// 该类只做少量 UIKit 中继、不含热点计算，跳过优化对性能无损失，
    /// 却能让整包保住 `-O`。
    @_optimize(none)
    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<AnyView>?
        fileprivate var contentConfiguration: ContentConfiguration?
        private var tab: VideoDetailContentTab?
        private var onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
        private var onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
        private var appliedScrollAdjustmentToken: Int?
        private var isApplyingScrollAdjustment = false
        private var virtualScrollOffset: CGFloat = 0
        private var lastReportedVirtualScrollOffset: CGFloat?
        private var pendingReportedScroll: (tab: VideoDetailContentTab, offset: CGFloat)?
        private var isReportScheduled = false
        private var hasUserScrolled = false
        private var isUpdatingView = false

        fileprivate func update(
            scrollView: UIScrollView,
            tab: VideoDetailContentTab,
            scrollAdjustment: VideoDetailScrollAdjustment?,
            onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?,
            onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?,
            bottomInset: CGFloat,
            contentConfiguration: ContentConfiguration
        ) {
            isUpdatingView = true
            defer { isUpdatingView = false }
            let tabChanged = self.tab != tab
            self.tab = tab
            self.onScrollOffsetChange = onScrollOffsetChange
            self.onScrollPhaseChange = onScrollPhaseChange
            self.contentConfiguration = contentConfiguration
            if tabChanged {
                lastReportedVirtualScrollOffset = nil
                pendingReportedScroll = nil
            }
            let resolvedBottomInset = max(bottomInset, 0)
            if scrollView.contentInset.bottom != resolvedBottomInset {
                scrollView.contentInset.bottom = resolvedBottomInset
                scrollView.verticalScrollIndicatorInsets.bottom = resolvedBottomInset
            }

            if !scrollView.isTracking && !scrollView.isDecelerating {
                applyVirtualScrollOffset(virtualScrollOffset, to: scrollView)
            }

            guard let scrollAdjustment,
                  scrollAdjustment.tab == tab,
                  appliedScrollAdjustmentToken != scrollAdjustment.token
            else { return }
            appliedScrollAdjustmentToken = scrollAdjustment.token
            applyVirtualScrollOffset(scrollAdjustment.offset, to: scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard let tab else { return }
            hasUserScrolled = true
            onScrollPhaseChange?(tab, .tracking)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isApplyingScrollAdjustment, let tab else { return }

            guard hasUserScrolled else {
                applyVirtualScrollOffset(0, to: scrollView)
                return
            }

            virtualScrollOffset = max(0, scrollView.contentOffset.y)

            reportScrollOffset(
                tab: tab,
                offset: virtualScrollOffset,
                immediately: !isUpdatingView && (scrollView.isDragging || scrollView.isDecelerating)
            )
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard let tab else { return }
            onScrollPhaseChange?(tab, decelerate ? .decelerating : .idle)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let tab else { return }
            applyVirtualScrollOffset(max(0, scrollView.contentOffset.y), to: scrollView)
            if hasUserScrolled {
                reportScrollOffset(tab: tab, offset: virtualScrollOffset)
            }
            onScrollPhaseChange?(tab, .idle)
        }

        private func applyVirtualScrollOffset(
            _ offset: CGFloat,
            to scrollView: UIScrollView
        ) {
            let normalizedOffset = max(offset, 0)
            virtualScrollOffset = normalizedOffset
            let contentOffset = normalizedOffset

            guard abs(scrollView.contentOffset.y - contentOffset) > 0.5 else { return }
            isApplyingScrollAdjustment = true
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: contentOffset),
                animated: false
            )
            isApplyingScrollAdjustment = false
        }

        private func reportScrollOffset(
            tab: VideoDetailContentTab,
            offset: CGFloat,
            immediately: Bool = false
        ) {
            guard lastReportedVirtualScrollOffset.map({ abs($0 - offset) > 0.5 }) ?? true else {
                return
            }
            lastReportedVirtualScrollOffset = offset
            if immediately {
                pendingReportedScroll = nil
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    onScrollOffsetChange?(tab, offset)
                }
                return
            }
            pendingReportedScroll = (tab, offset)
            guard !isReportScheduled else { return }
            isReportScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isReportScheduled = false
                guard let report = self.pendingReportedScroll
                else { return }
                self.pendingReportedScroll = nil
                guard self.tab == report.tab else { return }
                self.onScrollOffsetChange?(report.tab, report.offset)
            }
        }
    }
}

private struct VideoDetailScrollingTabPage<Content: View>: View {
    let tab: VideoDetailContentTab
    let scrollAdjustment: VideoDetailScrollAdjustment?
    let onScrollOffsetChange: ((VideoDetailContentTab, CGFloat) -> Void)?
    let onScrollPhaseChange: ((VideoDetailContentTab, ScrollPhase) -> Void)?
    let summary: AnyView?
    let topInset: CGFloat
    let minimumPlayerHeight: CGFloat
    let bottomInset: CGFloat
    @ViewBuilder let content: (VideoDetailContentTab) -> Content
    @State private var position = ScrollPosition()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                scrollStack
                .padding(.top, 12)
                .frame(
                    minHeight: minimumScrollableContentHeight(viewportHeight: proxy.size.height),
                    alignment: .top
                )
                // iOS 15 上 `.contentMargins` 的兼容实现是空操作（直接返回 self），
                // 底部留白完全失效，评论列表末尾会被 iOS 15 回退底栏压住。
                // 这里用 padding 兜底等效留白；iOS 16+ 由 contentMargins 负责，不重复留白。
                .ios15ScrollContentBottomInset(bottomInset)
            }
            .environment(
                \.videoDetailCommentsEmptyStateMinimumHeight,
                topInset > 0 ? max(proxy.size.height - bottomInset, 0) : 0
            )
            .scrollPosition($position)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .scrollIndicators(.hidden)
            .nativeTopScrollEdgeEffect()
            .onScrollGeometryChange(for: CGFloat.self) {
                max(0, $0.contentOffset.y + $0.contentInsets.top)
            } action: { _, offset in
                onScrollOffsetChange?(tab, offset)
            }
            .onScrollPhaseChange { _, phase in
                onScrollPhaseChange?(tab, phase)
            }
            .onChange(of: scrollAdjustment) { _, adjustment in
                guard let adjustment, adjustment.tab == tab else { return }
                position.scrollTo(y: adjustment.offset)
            }
        }
    }

    private func minimumScrollableContentHeight(viewportHeight: CGFloat) -> CGFloat {
        VideoDetailShellLayout.scrollContentMinimumHeight(
            viewportHeight: viewportHeight,
            expandedPlayerHeight: topInset,
            minimumPlayerHeight: minimumPlayerHeight
        )
    }

    @ViewBuilder
    private var scrollStack: some View {
        if topInset > 0, minimumPlayerHeight > 0 {
            LazyVStack(spacing: 12) {
                Color.clear
                    .frame(height: topInset)
                    .accessibilityHidden(true)
                summary
                content(tab)
            }
        } else {
            LazyVStack(spacing: 12) {
                summary
                content(tab)
            }
        }
    }
}

private struct VideoDetailToolbarCommentComposerButton: View {
    /// 按钮边长。与 `VideoDetailToolbarSegmentedPickerView.height` 保持一致，
    /// 使 iOS 15 回退底栏的总高等于切换器高度 + 上下留白，不再被按钮撑高。
    static let size: CGFloat = VideoDetailToolbarSegmentedPickerView.height

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .frame(width: Self.size, height: Self.size)
        }
        .tint(.primary)
        .accessibilityLabel("发表评论")
        .accessibilityIdentifier("video.detail.toolbar-comment-compose")
    }
}

private struct VideoDetailToolbarCommentRefreshButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .frame(
                    width: VideoDetailToolbarCommentComposerButton.size,
                    height: VideoDetailToolbarCommentComposerButton.size
                )
        }
        .tint(.primary)
        .accessibilityLabel("刷新评论")
        .accessibilityIdentifier("video.detail.toolbar-comment-refresh")
    }
}

/// iOS 15 专用：替代系统 bottomBar toolbar 的显式底栏。
/// 版式对齐系统 toolbar 的原始排布（刷新/发表评论 + 居中的「简介 | 评论」切换器）。
private struct VideoDetailIOS15BottomToolbar: View {
    @Binding var selection: VideoDetailContentTab
    let onRefreshComments: () -> Void
    let onOpenCommentComposer: (() -> Void)?

    private static let buttonSize = VideoDetailToolbarCommentComposerButton.size

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if selection == .comments {
                    VideoDetailToolbarCommentRefreshButton(action: onRefreshComments)
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.buttonSize, height: Self.buttonSize)

            VideoDetailToolbarSegmentedPickerView(selection: $selection)
                .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)

            Group {
                if selection == .comments, let onOpenCommentComposer {
                    VideoDetailToolbarCommentComposerButton(action: onOpenCommentComposer)
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.buttonSize, height: Self.buttonSize)
        }
        .padding(.horizontal, 12)
        .padding(.top, Self.verticalPadding)
        .padding(.bottom, Self.verticalPadding + bottomSafeAreaInset)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
        .animation(.smooth(duration: 0.22), value: selection)
        .accessibilityIdentifier("video.detail.ios15-bottom-toolbar")
    }

    /// 底栏贴屏幕下沿绘制，正文需让开底部安全区（iPhone 6s 等实体 Home 键机型为 0）。
    private var bottomSafeAreaInset: CGFloat {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }

    /// iOS 15 回退底栏实际占用的高度，供滚动内容让位使用。
    static func ios15BottomBarHeight(includingSafeArea safeAreaBottom: CGFloat) -> CGFloat {
        VideoDetailToolbarSegmentedPickerView.height + Self.verticalPadding * 2 + max(safeAreaBottom, 0)
    }

    private static let verticalPadding: CGFloat = 4
}

private extension View {
    /// 仅在 iOS 15 及以下为滚动内容补底部留白。
    ///
    /// `.contentMargins(_:for:)` 是 iOS 17 API，本工程的 iOS 15 兼容层把它实现成
    /// 空操作（`return self`），因此在 iOS 15 上底部留白完全不生效——iOS 15 回退底栏
    /// 是以 `.overlay` 形式盖在内容上方的，评论列表末尾会被压住看不见。
    /// iOS 16+ 走系统 toolbar + 真实 `contentMargins`，此处不重复留白，避免出现双倍空白。
    @ViewBuilder
    func ios15ScrollContentBottomInset(_ inset: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self
        } else {
            padding(.bottom, max(inset, 0))
        }
    }
}
