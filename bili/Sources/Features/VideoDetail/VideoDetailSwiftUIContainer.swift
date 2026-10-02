import Combine
import CoreGraphics
import SwiftUI
import UIKit

@MainActor
final class VideoDetailSwiftUIContainerModel: ObservableObject {
    let viewModel: VideoDetailViewModel
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let rotationCoordinator: PlaybackRotationCoordinator
    let contentUpdateGate: VideoDetailContentUpdateGate
    let contentState = VideoDetailShellContentView.State()
    @Published private(set) var activePlayerViewModel: PlayerStateViewModel?
    @Published private(set) var surfacePlayerViewModel: PlayerStateViewModel?
    @Published private(set) var videoAspectRatio: CGFloat
    @Published private(set) var currentPlayerHeight: CGFloat?
    private(set) var lastScrollOffset: CGFloat = 0
    @Published private(set) var isCollapsedChromeActive = false
    @Published private(set) var isPlaybackActiveSnapshot = false
    @Published private(set) var isBareSurfaceTransitionActive = false
    @Published private(set) var retainsChromeDuringBareSurfaceTransition = false
    private(set) var playerFrame = CGRect.zero
#if DEBUG
    let playerFrameUpdates = CurrentValueSubject<CGRect, Never>(.zero)
#endif
    @Published var rootSafeAreaInsets = UIEdgeInsets.zero
    private(set) var interactiveScrollOffset: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()
    private var playbackStateCancellables = Set<AnyCancellable>()
    private var aspectRatioCancellables = Set<AnyCancellable>()
    private var scrollOffsets: [VideoDetailContentTab: CGFloat] = [:]
    private var interactiveScrollOffsets: [VideoDetailContentTab: CGFloat] = [:]
    private var visitedContentTabs: Set<VideoDetailContentTab>
    private var activeContentTab: VideoDetailContentTab
    private var pendingInteractiveTab: VideoDetailContentTab?
    private var pendingInteractiveTabOffset: CGFloat = 0
    private var isBackgroundRenderFreezeActive = false
    private var layoutSynchronizationScheduled = false
    private var pendingLayout: VideoDetailShellLayout?

    init(
        viewModel: VideoDetailViewModel,
        initialVideo: VideoItem,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        rotationCoordinator: PlaybackRotationCoordinator,
        initialContentTab: VideoDetailContentTab
    ) {
        self.viewModel = viewModel
        self.runtimeSettings = runtimeSettings
        self.rotationCoordinator = rotationCoordinator
        contentUpdateGate = VideoDetailContentUpdateGate()
        let initialPlayerViewModel = viewModel.playbackSession.activePlayer
        videoAspectRatio = VideoDetailInitialVideoGeometry.metadataAspectRatio(for: initialVideo)
            ?? VideoDetailInitialVideoGeometry.metadataAspectRatio(for: viewModel.detail)
            ?? initialPlayerViewModel?.videoAspectRatio
            ?? VideoDetailInitialVideoGeometry.defaultAspectRatio
        activePlayerViewModel = initialPlayerViewModel
        surfacePlayerViewModel = initialPlayerViewModel
        visitedContentTabs = [initialContentTab]
        activeContentTab = initialContentTab
        bind()
        bindVideoAspectRatio(to: initialPlayerViewModel)
        bindPlaybackState(to: initialPlayerViewModel)
    }

    var isInteractiveScrollCollapseActive: Bool {
        VideoDetailShellLayout.supportsInteractiveCollapse(
            videoAspectRatio: videoAspectRatio,
            isPlaybackActive: isPlaybackActiveSnapshot
        )
    }

    func setSecondaryContentMounted(_ mounted: Bool) {
        contentState.mountsSecondaryContent = mounted
    }

    func setBackgroundRenderFreezeActive(_ active: Bool) {
        isBackgroundRenderFreezeActive = active
        setContentUpdatesDeferred(false)
    }

    func beginSystemRotation(toLandscape: Bool) {
        isBareSurfaceTransitionActive = true
        retainsChromeDuringBareSurfaceTransition = true
        contentState.suppressesInteractiveContentActions = true
        if !toLandscape {
            currentPlayerHeight = nil
        }
    }

    func finishSystemRotation() {
        isBareSurfaceTransitionActive = false
        retainsChromeDuringBareSurfaceTransition = false
        contentState.suppressesInteractiveContentActions = false
    }

    func recoverStableLayout() {
        isBareSurfaceTransitionActive = false
        retainsChromeDuringBareSurfaceTransition = false
        contentState.suppressesInteractiveContentActions = false
    }

    func setContentUpdatesDeferred(_ deferred: Bool) {
        let shouldDefer = deferred || isBackgroundRenderFreezeActive
        viewModel.setContentRenderUpdatesDeferred(shouldDefer)
        viewModel.setPlaybackRenderUpdatesDeferred(shouldDefer)
        contentUpdateGate.setUpdatesDeferred(shouldDefer)
    }

    func layout(
        in size: CGSize,
        safeAreaTop: CGFloat,
        topInsetAlreadyApplied: CGFloat,
        rotationCoordinator: PlaybackRotationCoordinator
    ) -> VideoDetailShellLayout {
        let effectiveInteractiveOffset = isInteractiveScrollCollapseActive
            ? interactiveScrollOffset
            : nil
        let effectivePlayerHeight = effectiveInteractiveOffset.map {
            interactivePlayerHeight(forOffset: $0, bounds: size)
        } ?? currentPlayerHeight
        return VideoDetailShellLayout.resolve(
            bounds: CGRect(origin: .zero, size: size),
            safeAreaTop: safeAreaTop,
            topInsetAlreadyApplied: topInsetAlreadyApplied,
            videoAspectRatio: videoAspectRatio,
            currentPlayerHeight: effectivePlayerHeight,
            isPlaybackActive: isPlaybackActiveForLayout,
            isLandscape: rotationCoordinator.layoutLandscape,
            isPortraitFullscreen: rotationCoordinator.isPortraitFullscreen
        )
    }

    /// 当前 SwiftUI 坐标区域原点相对窗口顶部的偏移。
    ///
    /// iOS 15 的兼容层无法真正实现 `UIHostingController.safeAreaRegions = []`（该 API
    /// iOS 16 才有，兼容层里是空实现），若内容树未被铺满整屏，SwiftUI 内容会被安全区整体
    /// 下移，区域原点即等于这段偏移量。布局里的 `safeAreaTop` 必须扣掉这一部分，否则同一段
    /// 安全区会被计算两遍：真机（iPhone 6s / iOS 15.8.8）实测区域原点 64pt（状态栏 20 +
    /// 空导航栏 44），播放器再下移 64pt，视频顶部落在屏幕下 128pt 处，即「上方空出大黑边」。
    ///
    /// 配合 `ignoresSafeArea(.container, edges: .all)` 使用：铺满整屏时该值为 0（走正常路径），
    /// 一旦铺满失效则回落到这里的去重逻辑，两种情况都能把安全区只算一次。
    func appliedTopInset(regionTopInWindow: CGFloat) -> CGFloat {
        max(0, regionTopInWindow)
    }

    func storedInteractiveScrollOffset(for tab: VideoDetailContentTab) -> CGFloat {
        interactiveScrollOffsets[tab] ?? 0
    }

    func shouldShowCollapsedChrome(
        for layout: VideoDetailShellLayout,
        bounds: CGSize
    ) -> Bool {
        guard !isPlaybackActiveSnapshot else { return false }
        guard isInteractiveScrollCollapseActive else { return isCollapsedChromeActive }
        let standard = VideoDetailShellLayout.standardPlayerHeight(forWidth: bounds.width)
        return !rotationCoordinator.layoutLandscape
            && layout.playerFrame.height <= standard - 4
            && layout.playerFrame.height > 0
    }

    func collapsedChromeOpacity(
        for layout: VideoDetailShellLayout,
        bounds: CGSize
    ) -> Double {
        guard !isPlaybackActiveSnapshot,
              !rotationCoordinator.layoutLandscape,
              shouldShowCollapsedChrome(for: layout, bounds: bounds)
        else { return 0 }

        let standard = VideoDetailShellLayout.standardPlayerHeight(forWidth: bounds.width)
        let minimum = minimumPlayerHeight(forWidth: bounds.width)
        let distance = max(standard - minimum, 1)
        return max(0, min(1, Double((standard - layout.playerFrame.height) / distance)))
    }

    func synchronize(layout: VideoDetailShellLayout) {
#if DEBUG
        if playerFrame != layout.playerFrame {
            print(
                "[VideoDetailGeometry] coordinates=SwiftUI-root playerFrame=\(layout.playerFrame) "
                    + "contentFrame=\(layout.contentFrame) safeArea=\(rootSafeAreaInsets)"
            )
        }
#endif
        if playerFrame != layout.playerFrame {
            playerFrame = layout.playerFrame
#if DEBUG
            playerFrameUpdates.send(playerFrame)
#endif
        }
        if contentState.hidesBottomToolbar != layout.usesFullscreenLayout {
            contentState.hidesBottomToolbar = layout.usesFullscreenLayout
        }
        guard let contentTopInset = layout.contentTopInset else { return }
        guard abs(contentState.topInset - contentTopInset) > 0.5 else { return }
        contentState.topInset = contentTopInset
    }

    func scheduleLayoutSynchronization(_ layout: VideoDetailShellLayout) {
        pendingLayout = layout
        guard !layoutSynchronizationScheduled else { return }
        layoutSynchronizationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutSynchronizationScheduled = false
            guard let layout = self.pendingLayout else { return }
            self.pendingLayout = nil
            self.synchronize(layout: layout)
        }
    }

    func handleSelectedTabChange(
        _ tab: VideoDetailContentTab,
        bounds: CGSize,
        rotationCoordinator: PlaybackRotationCoordinator
    ) {
        activeContentTab = tab
        guard !rotationCoordinator.isTransitioning,
              !rotationCoordinator.layoutLandscape,
              !rotationCoordinator.isPortraitFullscreen
        else { return }

        if isInteractiveScrollCollapseActive {
            let targetOffset: CGFloat
            if pendingInteractiveTab == tab {
                targetOffset = pendingInteractiveTabOffset
            } else {
                targetOffset = prepareInteractiveTabChange(to: tab, bounds: bounds)
            }
            contentState.requestScrollAdjustment(tab: tab, offset: targetOffset)
            return
        }

        if visitedContentTabs.contains(tab) {
            if let preservedOffset = scrollOffsets[tab] {
                lastScrollOffset = preservedOffset
                if preservedOffset <= 0.5 {
                    currentPlayerHeight = nil
                } else {
                    applyPlayerHeight(forOffset: preservedOffset, bounds: bounds)
                }
                contentState.requestScrollAdjustment(tab: tab, offset: preservedOffset)
                updateCollapsedChrome(bounds: bounds)
            }
            return
        }

        visitedContentTabs.insert(tab)
        let expanded = expandedPlayerHeight(bounds: bounds)
        let current = resolvedPlayerHeight(bounds: bounds)
        let targetOffset = max(0, expanded - current)
        lastScrollOffset = targetOffset
        Task { @MainActor [weak self, weak rotationCoordinator] in
            guard let self,
                  rotationCoordinator?.isTransitioning == false
            else { return }
            self.contentState.requestScrollAdjustment(tab: tab, offset: targetOffset)
        }
    }

    @discardableResult
    func prepareInteractiveTabChange(
        to tab: VideoDetailContentTab,
        bounds: CGSize
    ) -> CGFloat {
        guard isInteractiveScrollCollapseActive else { return 0 }

        let expanded = expandedPlayerHeight(bounds: bounds)
        let minimum = minimumPlayerHeight(forWidth: bounds.width)
        let currentMetrics = VideoDetailShellLayout.interactiveScrollMetrics(
            scrollOffset: interactiveScrollOffset,
            expandedPlayerHeight: expanded,
            minimumPlayerHeight: minimum
        )
        let storedOffset = storedInteractiveScrollOffset(for: tab)
        let targetOffset: CGFloat
        if storedOffset > currentMetrics.collapseDistance + 0.5 {
            targetOffset = storedOffset
        } else {
            targetOffset = currentMetrics.collapseOffset
        }
        guard pendingInteractiveTab != tab
            || abs(pendingInteractiveTabOffset - targetOffset) > 0.5
        else { return targetOffset }
        pendingInteractiveTab = tab
        pendingInteractiveTabOffset = targetOffset
        setInteractiveScrollOffset(targetOffset, for: tab)
        updateCollapsedChrome(bounds: bounds)
        return targetOffset
    }

    func handleScrollOffset(
        tab: VideoDetailContentTab,
        offset: CGFloat,
        selectedTab: VideoDetailContentTab,
        bounds: CGSize,
        rotationCoordinator: PlaybackRotationCoordinator
    ) {
        scrollOffsets[tab] = offset
        guard tab == selectedTab,
              !rotationCoordinator.isTransitioning,
              !rotationCoordinator.layoutLandscape,
              !rotationCoordinator.isPortraitFullscreen
        else { return }

        let previousOffset = lastScrollOffset
        lastScrollOffset = offset
        if offset <= 0.5 {
            lastScrollOffset = 0
            if previousOffset > 0.5 {
                currentPlayerHeight = nil
            }
        } else {
            applyPlayerHeight(forOffset: offset, bounds: bounds)
        }
        updateCollapsedChrome(bounds: bounds)
    }

    func recordInteractiveScrollOffset(
        tab: VideoDetailContentTab,
        offset: CGFloat,
        selectedTab: VideoDetailContentTab,
        bounds: CGSize
    ) {
        applyInteractiveScrollOffset(
            tab: tab,
            offset: offset,
            selectedTab: selectedTab,
            bounds: bounds
        )
    }

    private func applyInteractiveScrollOffset(
        tab: VideoDetailContentTab,
        offset: CGFloat,
        selectedTab: VideoDetailContentTab,
        bounds: CGSize
    ) {
        let normalizedOffset = max(0, offset)
        activeContentTab = selectedTab
        guard tab == selectedTab else {
            interactiveScrollOffsets[tab] = normalizedOffset
            return
        }

        if pendingInteractiveTab == tab {
            guard normalizedOffset + 0.5 >= pendingInteractiveTabOffset else { return }
            pendingInteractiveTab = nil
            pendingInteractiveTabOffset = 0
        }

        let previousHeight = interactivePlayerHeight(forOffset: interactiveScrollOffset, bounds: bounds)
        let nextHeight = interactivePlayerHeight(forOffset: normalizedOffset, bounds: bounds)
        setInteractiveScrollOffset(
            normalizedOffset,
            for: tab,
            updatesLayout: isInteractiveScrollCollapseActive && abs(previousHeight - nextHeight) > 0.5
        )
        updateCollapsedChrome(bounds: bounds)
    }

    func handleInteractiveScrollPhase(
        tab: VideoDetailContentTab,
        phase: ScrollPhase,
        selectedTab: VideoDetailContentTab
    ) {
        guard tab == selectedTab else { return }
        if phase == .tracking || phase == .interacting {
            pendingInteractiveTab = nil
            pendingInteractiveTabOffset = 0
        }
    }

    func updateCollapsedChrome(bounds: CGSize) {
        let playerHeight: CGFloat
        if isInteractiveScrollCollapseActive {
            playerHeight = interactivePlayerHeight(
                forOffset: interactiveScrollOffset,
                bounds: bounds
            )
        } else {
            playerHeight = resolvedPlayerHeight(bounds: bounds)
        }
        let standard = VideoDetailShellLayout.standardPlayerHeight(forWidth: bounds.width)
        let showsCollapsedChrome = !rotationCoordinator.layoutLandscape
            && !isPlaybackActiveSnapshot
            && playerHeight <= standard - 4
            && playerHeight > 0
        if isCollapsedChromeActive != showsCollapsedChrome {
            isCollapsedChromeActive = showsCollapsedChrome
        }
    }

    private var isPlaybackActive: Bool {
        isPlaybackActiveSnapshot
    }

    private var isPlaybackActiveForLayout: Bool {
        isPlaybackActive
    }

    private func bind() {
        viewModel.objectWillChange
            .sink { [weak contentUpdateGate] _ in
                contentUpdateGate?.receiveUpdate()
            }
            .store(in: &cancellables)

        viewModel.$detail
            .receive(on: RunLoop.main)
            .sink { [weak self] detail in
                guard let self else { return }
                let ratio = VideoDetailInitialVideoGeometry.metadataAspectRatio(for: detail)
                    ?? self.surfacePlayerViewModel?.videoAspectRatio
                guard let ratio, ratio.isFinite, ratio > 0.1,
                      abs(self.videoAspectRatio - ratio) > 0.001
                else { return }
                self.videoAspectRatio = ratio
                self.currentPlayerHeight = nil
            }
            .store(in: &cancellables)

        viewModel.playbackSession.$activePlayer
            .receive(on: RunLoop.main)
            .sink { [weak self] player in
                guard let self else { return }
                self.activePlayerViewModel = player
                if let player {
                    self.surfacePlayerViewModel = player
                }
                self.bindVideoAspectRatio(to: player)
                self.bindPlaybackState(to: player ?? self.surfacePlayerViewModel)
            }
            .store(in: &cancellables)
    }

    private func bindVideoAspectRatio(to player: PlayerStateViewModel?) {
        aspectRatioCancellables.removeAll()
        guard let player else { return }

        applyPlayerAspectRatioIfNeeded(player.videoAspectRatio)
        player.$videoPresentationSize
            .receive(on: RunLoop.main)
            .sink { [weak self, weak player] _ in
                guard let self, let player else { return }
                self.applyPlayerAspectRatioIfNeeded(player.videoAspectRatio)
            }
            .store(in: &aspectRatioCancellables)
    }

    private func applyPlayerAspectRatioIfNeeded(_ ratio: CGFloat?) {
        guard VideoDetailInitialVideoGeometry.metadataAspectRatio(for: viewModel.detail) == nil,
              let ratio,
              ratio.isFinite,
              ratio > 0.1,
              abs(videoAspectRatio - ratio) > 0.001
        else { return }
        videoAspectRatio = ratio
        currentPlayerHeight = nil
    }

    private func bindPlaybackState(to player: PlayerStateViewModel?) {
        playbackStateCancellables.removeAll()
        guard let player else {
            updatePlaybackActivity(false)
            return
        }

        let updatePlaybackState: (Bool, Bool) -> Void = { [weak self] isPlaying, isUserSeeking in
            self?.updatePlaybackActivity(isPlaying || isUserSeeking)
        }
        updatePlaybackState(player.isPlaying, player.isUserSeeking)
        player.$isPlaying
            .combineLatest(player.$isUserSeeking)
            .removeDuplicates { lhs, rhs in lhs == rhs }
            .sink { isPlaying, isUserSeeking in
                updatePlaybackState(isPlaying, isUserSeeking)
            }
            .store(in: &playbackStateCancellables)
    }

    private func expandedPlayerHeight(bounds: CGSize) -> CGFloat {
        VideoDetailShellLayout.expandedPlayerHeight(
            bounds: bounds,
            videoAspectRatio: videoAspectRatio
        )
    }

    private func minimumPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        VideoDetailShellLayout.minimumPlayerHeight(
            forWidth: width,
            isPlaybackActive: isPlaybackActiveForLayout
        )
    }

    private func resolvedPlayerHeight(bounds: CGSize) -> CGFloat {
        VideoDetailShellLayout.resolvedPlayerHeight(
            bounds: bounds,
            videoAspectRatio: videoAspectRatio,
            currentPlayerHeight: currentPlayerHeight,
            isPlaybackActive: isPlaybackActiveForLayout
        )
    }

    private func applyPlayerHeight(forOffset offset: CGFloat, bounds: CGSize) {
        let target = interactivePlayerHeight(forOffset: offset, bounds: bounds)
        guard currentPlayerHeight.map({ abs($0 - target) > 0.5 }) ?? true else { return }
        currentPlayerHeight = target
    }

    private func interactivePlayerHeight(forOffset offset: CGFloat, bounds: CGSize) -> CGFloat {
        let expanded = expandedPlayerHeight(bounds: bounds)
        let minimum = minimumPlayerHeight(forWidth: bounds.width)
        let target = max(minimum, min(expanded, expanded - offset))
        return target
    }

    private func setInteractiveScrollOffset(
        _ offset: CGFloat,
        for tab: VideoDetailContentTab,
        updatesLayout: Bool = true
    ) {
        let normalizedOffset = max(0, offset)
        interactiveScrollOffsets[tab] = normalizedOffset
        guard abs(interactiveScrollOffset - normalizedOffset) > 0.5 else { return }
        if updatesLayout { objectWillChange.send() }
        interactiveScrollOffset = normalizedOffset
    }

    private func updatePlaybackActivity(_ isActive: Bool) {
        let wasInteractive = isInteractiveScrollCollapseActive
        guard isPlaybackActiveSnapshot != isActive else { return }

        if wasInteractive {
            lastScrollOffset = interactiveScrollOffset
        }
        isPlaybackActiveSnapshot = isActive

        guard !wasInteractive, isInteractiveScrollCollapseActive else { return }
        setInteractiveScrollOffset(lastScrollOffset, for: activeContentTab)
    }

}

@MainActor
private struct VideoDetailInteractivePlayerLayer: View {
    @ObservedObject var model: VideoDetailSwiftUIContainerModel
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    let viewModel: VideoDetailViewModel
    let size: CGSize
    let safeAreaTop: CGFloat
    let topInsetAlreadyApplied: CGFloat
    let selectedContentTab: VideoDetailContentTab
    let dependencies: AppDependencies
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void

    var body: some View {
        let layout = model.layout(
            in: size,
            safeAreaTop: safeAreaTop,
            topInsetAlreadyApplied: topInsetAlreadyApplied,
            rotationCoordinator: rotationCoordinator
        )
        let showsCollapsedChrome = model.shouldShowCollapsedChrome(
            for: layout,
            bounds: size
        )
        let collapsedChromeOpacity = model.collapsedChromeOpacity(
            for: layout,
            bounds: size
        )

        ZStack(alignment: .topLeading) {
            if let playerViewModel = model.surfacePlayerViewModel {
                VideoDetailShellSurfaceRepresentable(
                    playerViewModel: playerViewModel,
                    detailViewModel: viewModel,
                    dependencies: dependencies,
                    runtimeSettings: runtimeSettings,
                    rotationCoordinator: rotationCoordinator,
                    videoAspectRatio: model.videoAspectRatio,
                    isBareSurfaceTransitionActive: model.isBareSurfaceTransitionActive,
                    retainsChromeDuringBareSurfaceTransition: model.retainsChromeDuringBareSurfaceTransition,
                    isCollapsedChromeActive: showsCollapsedChrome,
                    onShowMoreControls: onShowMoreControls,
                    onDismissMoreControls: onDismissMoreControls,
                    onRequestFullscreen: onRequestFullscreen,
                    onExitFullscreen: onExitFullscreen,
                    onToggleDanmaku: onToggleDanmaku,
                    onShowDanmakuSettings: onShowDanmakuSettings,
                    onNavigateBack: onNavigateBack
                )
                .frame(width: layout.playerFrame.width, height: layout.playerFrame.height)
                .position(x: layout.playerFrame.midX, y: layout.playerFrame.midY)
                .zIndex(2)

                if showsCollapsedChrome && !layout.usesFullscreenLayout {
                    VideoDetailShellCollapsedBar(
                        playerViewModel: playerViewModel,
                        opacity: collapsedChromeOpacity,
                        onNavigateBack: onNavigateBack,
                        onRequestFullscreen: onRequestFullscreen
                    )
                    .frame(width: layout.playerFrame.width, height: layout.playerFrame.height)
                    .position(x: layout.playerFrame.midX, y: layout.playerFrame.midY)
                    .zIndex(3)
                }
            }

            VideoDetailGeometryDebugHUD(
                layout: layout,
                bounds: size,
                videoAspectRatio: model.videoAspectRatio,
                isLandscape: rotationCoordinator.layoutLandscape,
                isPortraitFullscreen: rotationCoordinator.isPortraitFullscreen,
                appliedTopInset: topInsetAlreadyApplied,
                safeAreaTop: safeAreaTop
            )
            .zIndex(99)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onChange(of: layout) { _, newLayout in
                guard newLayout.playerFrame != model.playerFrame else { return }
                model.scheduleLayoutSynchronization(newLayout)
            }
    }
}

/// 临时诊断浮层（诊断用，拿到数据后即移除）。
///
/// 连续四轮按猜测修改布局公式均未奏效，改为让 App 把决定性几何量直接画在屏幕上，
/// 依据真实数值定位，而不再推断。
@MainActor
private struct VideoDetailGeometryDebugHUD: View {
    let layout: VideoDetailShellLayout
    let bounds: CGSize
    let videoAspectRatio: CGFloat
    let isLandscape: Bool
    let isPortraitFullscreen: Bool
    let appliedTopInset: CGFloat
    let safeAreaTop: CGFloat

    var body: some View {
        let playerFrame = layout.playerFrame
        let text =
            "GEOM bounds \(Int(bounds.width))x\(Int(bounds.height))\n"
            + "player \(Int(playerFrame.width))x\(Int(playerFrame.height)) y=\(Int(playerFrame.minY))\n"
            + "aspect \(String(format: "%.3f", videoAspectRatio))\n"
            + "fs \(layout.usesFullscreenLayout) land \(isLandscape) pfs \(isPortraitFullscreen)\n"
            + "dedup \(Int(appliedTopInset)) safeTop \(Int(safeAreaTop)) cTop \(Int(layout.contentTopInset ?? -1))"
        return VStack(alignment: .leading) {
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.green)
                .padding(4)
                .background(Color.black.opacity(0.8))
            Spacer()
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

@MainActor
struct VideoDetailSwiftUIContainer: View {
    let viewModel: VideoDetailViewModel
    @ObservedObject var model: VideoDetailSwiftUIContainerModel
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    @Binding var selectedContentTab: VideoDetailContentTab
    let dependencies: AppDependencies
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onShowCoinPicker: () -> Void
    let onOpenCommentComposer: (Comment?) -> Void
    let onReply: (Comment) -> Void
    let openVideoOwnerRoute: ((VideoOwner) -> Void)?
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let isInteractiveScrollCollapseEnabled = model.isInteractiveScrollCollapseActive
            // 该区域相对窗口顶部的偏移量：iOS 15 下 SwiftUI 内容若未铺满整屏会被安全区整体
            // 下移，这段偏移必须从布局的 safeAreaTop 里扣掉，否则安全区会被算两次，视频顶部
            // 就会多出一条大黑边（真机实测 64pt）。
            let appliedTopInset = model.appliedTopInset(
                regionTopInWindow: proxy.frame(in: .global).minY
            )
            let layout = model.layout(
                in: proxy.size,
                safeAreaTop: model.rootSafeAreaInsets.top,
                topInsetAlreadyApplied: appliedTopInset,
                rotationCoordinator: rotationCoordinator
            )

            ZStack(alignment: .topLeading) {
                VideoDetailShellContentView(
                    viewModel: viewModel,
                    updateGate: model.contentUpdateGate,
                    runtimeSettings: runtimeSettings,
                    state: model.contentState,
                    layoutWidth: proxy.size.width,
                    placesTopInsetInScrollContent: true,
                    // Keep the scroll host's content extent stable when playback pauses.
                    // The layout model still determines the player's actual minimum height.
                    interactiveMinimumPlayerHeight: VideoDetailShellLayout.collapsedToolbarHeight,
                    selectedContentTab: $selectedContentTab,
                    onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                    onShowFavoriteFolders: onShowFavoriteFolders,
                    onShowCoinPicker: onShowCoinPicker,
                    onOpenCommentComposer: onOpenCommentComposer,
                    onRefreshComments: {
                        Task { @MainActor in
                            await viewModel.retryComments()
                        }
                    },
                    onReply: onReply,
                    openVideoOwnerRoute: openVideoOwnerRoute,
                    onSelectedTabChange: { tab in
                        if isInteractiveScrollCollapseEnabled {
                            model.prepareInteractiveTabChange(to: tab, bounds: proxy.size)
                        }
                        DispatchQueue.main.async {
                            model.handleSelectedTabChange(
                                tab,
                                bounds: proxy.size,
                                rotationCoordinator: rotationCoordinator
                            )
                        }
                    },
                    onSelectionWillChange: { tab in
                        guard isInteractiveScrollCollapseEnabled else { return }
                        model.prepareInteractiveTabChange(to: tab, bounds: proxy.size)
                    },
                    onScrollOffsetChange: { tab, offset in
                        if isInteractiveScrollCollapseEnabled {
                            model.recordInteractiveScrollOffset(
                                tab: tab,
                                offset: offset,
                                selectedTab: selectedContentTab,
                                bounds: proxy.size
                            )
                        } else {
                            DispatchQueue.main.async {
                                model.handleScrollOffset(
                                    tab: tab,
                                    offset: offset,
                                    selectedTab: selectedContentTab,
                                    bounds: proxy.size,
                                    rotationCoordinator: rotationCoordinator
                                )
                            }
                        }
                    },
                    onScrollPhaseChange: { tab, phase in
                        guard isInteractiveScrollCollapseEnabled else { return }
                        model.handleInteractiveScrollPhase(
                            tab: tab,
                            phase: phase,
                            selectedTab: selectedContentTab
                        )
                    }
                )
                .frame(
                    width: layout.contentFrame.width,
                    height: layout.contentFrame.height
                )
                .position(x: layout.contentFrame.midX, y: layout.contentFrame.midY)
                .opacity(layout.usesFullscreenLayout ? 0 : 1)
                .allowsHitTesting(
                    !layout.usesFullscreenLayout
                        && !model.contentState.suppressesInteractiveContentActions
                )

                VideoDetailInteractivePlayerLayer(
                    model: model,
                    rotationCoordinator: rotationCoordinator,
                    viewModel: viewModel,
                    size: proxy.size,
                    safeAreaTop: model.rootSafeAreaInsets.top,
                    topInsetAlreadyApplied: appliedTopInset,
                    selectedContentTab: selectedContentTab,
                    dependencies: dependencies,
                    runtimeSettings: runtimeSettings,
                    onShowMoreControls: onShowMoreControls,
                    onDismissMoreControls: onDismissMoreControls,
                    onRequestFullscreen: onRequestFullscreen,
                    onExitFullscreen: onExitFullscreen,
                    onToggleDanmaku: onToggleDanmaku,
                    onShowDanmakuSettings: onShowDanmakuSettings,
                    onNavigateBack: onNavigateBack
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onAppear {
                DispatchQueue.main.async {
                    model.synchronize(layout: layout)
                    model.updateCollapsedChrome(bounds: proxy.size)
                }
            }
        }
        // iOS 15 没有 `UIHostingController.safeAreaRegions`（兼容层里是空实现），改用 SwiftUI
        // 自带的等价开关让整棵内容树铺满整屏，与 iOS 16+ 的 `safeAreaRegions = []` 行为对齐。
        // 只在 container 区域内铺满、不动 keyboard，避免影响评论输入的键盘避让。
        .ignoresSafeArea(.container, edges: .all)
        .background(.black)
    }
}

@MainActor
protocol VideoDetailRotationBridgeDelegate: AnyObject {
    func requestVideoDetailFullscreen()
    func requestVideoDetailExitFullscreen()
    func navigateBackFromVideoDetail()
}

/// SwiftUI 内容树的 UIKit 宿主。
///
/// 该控制器只负责承载 SwiftUI 和转发内容层回调；方向请求仍由外层
/// `VideoDetailRotationBridgeViewController` 统一处理。
@MainActor
final class VideoDetailSwiftUIContainerViewController: UIViewController {
    let viewModel: VideoDetailViewModel
    let contentModel: VideoDetailSwiftUIContainerModel
    let rotationCoordinator: PlaybackRotationCoordinator

    weak var rotationDelegate: (any VideoDetailRotationBridgeDelegate)?

    private let runtimeSettings: VideoDetailRuntimeSettingsStore
    private let dependencies: AppDependencies
    private let selectedContentTab: Binding<VideoDetailContentTab>
    private let openVideoOwnerRoute: ((VideoOwner) -> Void)?
    private let onShowNetworkDiagnostics: () -> Void
    private let onShowFavoriteFolders: () -> Void
    private let onShowCoinPicker: () -> Void
    private let onOpenCommentComposer: (Comment?) -> Void
    private let onShowDanmakuSettings: () -> Void
    private let onReply: (Comment) -> Void
    private let onPresentPlayerMoreControls: (PlayerStateViewModel, @escaping () -> Void) -> Void
    private let onDismissPlayerMoreControls: () -> Void
    private let onToggleDanmaku: () -> Void
    private let onNavigateBack: () -> Void
    private let playbackDiagnostics = VideoDetailPlaybackDiagnostics()
    private var cancellables = Set<AnyCancellable>()

#if DEBUG
    private let rotationDiagnosticsAccessibilityView = UILabel()
    private let playerFrameDiagnosticsAccessibilityView = UIView()
#endif

    private lazy var hostingController: UIHostingController<VideoDetailSwiftUIContainer> = {
        UIHostingController(rootView: makeRootView())
    }()

    init(
        initialVideo: VideoItem,
        viewModel: VideoDetailViewModel,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        dependencies: AppDependencies,
        rotationCoordinator: PlaybackRotationCoordinator,
        openVideoOwnerRoute: ((VideoOwner) -> Void)?,
        selectedContentTab: Binding<VideoDetailContentTab>,
        onShowNetworkDiagnostics: @escaping () -> Void,
        onShowFavoriteFolders: @escaping () -> Void,
        onShowCoinPicker: @escaping () -> Void,
        onOpenCommentComposer: @escaping (Comment?) -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onPresentPlayerMoreControls: @escaping (PlayerStateViewModel, @escaping () -> Void) -> Void,
        onDismissPlayerMoreControls: @escaping () -> Void,
        onReply: @escaping (Comment) -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.runtimeSettings = runtimeSettings
        self.dependencies = dependencies
        self.selectedContentTab = selectedContentTab
        self.openVideoOwnerRoute = openVideoOwnerRoute
        self.onShowNetworkDiagnostics = onShowNetworkDiagnostics
        self.onShowFavoriteFolders = onShowFavoriteFolders
        self.onShowCoinPicker = onShowCoinPicker
        self.onOpenCommentComposer = onOpenCommentComposer
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.onPresentPlayerMoreControls = onPresentPlayerMoreControls
        self.onDismissPlayerMoreControls = onDismissPlayerMoreControls
        self.onReply = onReply
        self.onToggleDanmaku = onToggleDanmaku
        self.onNavigateBack = onNavigateBack
        self.rotationCoordinator = rotationCoordinator
        contentModel = VideoDetailSwiftUIContainerModel(
            viewModel: viewModel,
            initialVideo: initialVideo,
            runtimeSettings: runtimeSettings,
            rotationCoordinator: rotationCoordinator,
            initialContentTab: selectedContentTab.wrappedValue
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(hostingController)
        hostingController.safeAreaRegions = []
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
#if DEBUG
        rotationDiagnosticsAccessibilityView.isAccessibilityElement = true
        rotationDiagnosticsAccessibilityView.accessibilityIdentifier = "ui.videoDetail.rotationDiagnostics"
        rotationDiagnosticsAccessibilityView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        rotationDiagnosticsAccessibilityView.alpha = 0.01
        view.addSubview(rotationDiagnosticsAccessibilityView)
        playerFrameDiagnosticsAccessibilityView.isAccessibilityElement = true
        playerFrameDiagnosticsAccessibilityView.accessibilityIdentifier = "ui.videoDetail.playerFrame"
        playerFrameDiagnosticsAccessibilityView.isUserInteractionEnabled = false
        playerFrameDiagnosticsAccessibilityView.alpha = 0.01
        view.addSubview(playerFrameDiagnosticsAccessibilityView)
        contentModel.playerFrameUpdates
            .receive(on: RunLoop.main)
            .sink { [weak self] frame in
                guard let self else { return }
                self.playerFrameDiagnosticsAccessibilityView.frame = frame
                self.playerFrameDiagnosticsAccessibilityView.accessibilityValue = "height=\(frame.height)"
            }
            .store(in: &cancellables)
#endif
        contentModel.$activePlayerViewModel
            .receive(on: RunLoop.main)
            .sink { [weak self] player in
                self?.playbackDiagnostics.observe(player: player)
            }
            .store(in: &cancellables)
        playbackDiagnostics.begin(
            metricsID: viewModel.detail.bvid,
            title: viewModel.detail.title
        )
        Task { await viewModel.load() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let insets = view.safeAreaInsets
        if contentModel.rootSafeAreaInsets != insets {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.view.safeAreaInsets == insets else { return }
                self.contentModel.rootSafeAreaInsets = insets
                self.contentModel.contentState.bottomInset = insets.bottom
            }
        }
    }

    var activePlayerViewModel: PlayerStateViewModel? {
        contentModel.activePlayerViewModel
    }

    var playerFrame: CGRect {
        contentModel.playerFrame
    }

    var isPortraitVideo: Bool {
        contentModel.videoAspectRatio < 0.9
    }

    func setSecondaryContentMounted(_ mounted: Bool) {
        contentModel.setSecondaryContentMounted(mounted)
    }

    func setBackgroundRenderFreezeActive(_ active: Bool) {
        contentModel.setBackgroundRenderFreezeActive(active)
    }

    func beginSystemRotation(toLandscape: Bool) {
        contentModel.beginSystemRotation(toLandscape: toLandscape)
    }

    func finishSystemRotation() {
        contentModel.finishSystemRotation()
    }

    func recoverStableLayout() {
        contentModel.recoverStableLayout()
    }

    func dismissPlayerMoreControls() {
        onDismissPlayerMoreControls()
    }

    func presentPlayerMoreControls(onDismiss: @escaping () -> Void) {
        guard let player = activePlayerViewModel else {
            onDismiss()
            return
        }
        onPresentPlayerMoreControls(player, onDismiss)
    }

    func navigateBack() {
        onNavigateBack()
    }

    func suppressContentActionsDuringSystemBackGesture() {
        contentModel.contentState.suppressesInteractiveContentActions = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.contentModel.contentState.suppressesInteractiveContentActions = false
        }
    }

    func markRotationStarted(toLandscape: Bool) {
        playbackDiagnostics.markRotationStarted(toLandscape: toLandscape)
    }

    func markRotationFinished(toLandscape: Bool) {
        playbackDiagnostics.markRotationFinished(toLandscape: toLandscape)
        publishLatestRotationDiagnostic()
    }

    func markRotationRecovered(reason: String) {
        playbackDiagnostics.markRotationRecovered(reason: reason)
        publishLatestRotationDiagnostic()
    }

    func markPageDisappeared() {
        playbackDiagnostics.markPageDisappeared()
        publishLatestRotationDiagnostic()
    }

    func prepareForDismantle() {
        onDismissPlayerMoreControls()
        contentModel.setBackgroundRenderFreezeActive(false)
        playbackDiagnostics.markPageDisappeared()
        publishLatestRotationDiagnostic()
    }

    private func makeRootView() -> VideoDetailSwiftUIContainer {
        VideoDetailSwiftUIContainer(
            viewModel: viewModel,
            model: contentModel,
            runtimeSettings: runtimeSettings,
            rotationCoordinator: rotationCoordinator,
            selectedContentTab: selectedContentTab,
            dependencies: dependencies,
            onShowNetworkDiagnostics: onShowNetworkDiagnostics,
            onShowFavoriteFolders: onShowFavoriteFolders,
            onShowCoinPicker: onShowCoinPicker,
            onOpenCommentComposer: onOpenCommentComposer,
            onReply: onReply,
            openVideoOwnerRoute: openVideoOwnerRoute,
            onShowMoreControls: { [weak self] onDismiss in
                self?.presentPlayerMoreControls(onDismiss: onDismiss)
                    ?? onDismiss()
            },
            onDismissMoreControls: onDismissPlayerMoreControls,
            onRequestFullscreen: { [weak self] in
                self?.rotationDelegate?.requestVideoDetailFullscreen()
            },
            onExitFullscreen: { [weak self] in
                self?.rotationDelegate?.requestVideoDetailExitFullscreen()
            },
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: { [weak self] in
                self?.rotationDelegate?.navigateBackFromVideoDetail()
            }
        )
    }

    private func publishLatestRotationDiagnostic() {
#if DEBUG
        guard let record = playbackDiagnostics.completedRotationRecords.last,
              let data = try? JSONEncoder().encode(record),
              let value = String(data: data, encoding: .utf8)
        else { return }
        rotationDiagnosticsAccessibilityView.accessibilityValue = value
#endif
    }
}
