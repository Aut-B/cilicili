import CoreGraphics
import Foundation

/// 详情页播放器和内容区共享的几何模型。
///
/// 该类型不持有 View，也不触发状态写回。SwiftUI 内容区只消费
/// `contentTopInset`，UIKit surface 只消费 `playerFrame`，从而避免滚动时
/// 通过重建内容树反馈播放器高度。
@MainActor
struct VideoDetailShellLayout: Equatable {
    static let collapsedToolbarHeight: CGFloat = 54

    let playerFrame: CGRect
    let contentFrame: CGRect
    let contentTopInset: CGFloat?
    let usesFullscreenLayout: Bool

    static func standardPlayerHeight(forWidth width: CGFloat) -> CGFloat {
        (max(width, 0) * 9 / 16).rounded()
    }

    static func supportsInteractiveCollapse(
        videoAspectRatio: CGFloat,
        isPlaybackActive: Bool = false
    ) -> Bool {
        videoAspectRatio > 0 && (!isPlaybackActive || videoAspectRatio < 0.9)
    }

    static func scrollContentMinimumHeight(
        viewportHeight: CGFloat,
        expandedPlayerHeight: CGFloat,
        minimumPlayerHeight: CGFloat
    ) -> CGFloat {
        max(viewportHeight, 0)
            + max(expandedPlayerHeight - minimumPlayerHeight, 0)
    }

    static func interactiveScrollMetrics(
        scrollOffset: CGFloat,
        expandedPlayerHeight: CGFloat,
        minimumPlayerHeight: CGFloat
    ) -> VideoDetailInteractiveScrollMetrics {
        VideoDetailInteractiveScrollMetrics(
            scrollOffset: scrollOffset,
            expandedPlayerHeight: expandedPlayerHeight,
            minimumPlayerHeight: minimumPlayerHeight
        )
    }

    static func expandedPlayerHeight(
        bounds: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGFloat {
        let standard = standardPlayerHeight(forWidth: bounds.width)
        guard videoAspectRatio < 0.9 else {
            // 16:9 等横屏视频在竖屏下按真实比例撑满宽度：宽度给满、由此推出高度，
            // 播放器与画面同为 9:16，`.resizeAspect` 不再产生上下黑边。
            return aspectFillHeight(forWidth: bounds.width, videoAspectRatio: videoAspectRatio)
        }
        let proposed = max(bounds.height * 0.65, bounds.width)
        let maximum = max(standard, bounds.height * 0.72)
        return max(standard, min(proposed, maximum))
    }

    /// 竖屏下按视频真实宽高比推出的播放器高度（宽度铺满屏宽）。
    ///
    /// 旧实现对所有横屏视频一律使用 `width * 9/16` 的固定盒子，而播放器层的
    /// `videoGravity` 是 `.resizeAspect`（等比完整显示）。两者对非 16:9 素材不一致时，
    /// 画面无法填满盒子、上下（成比例不足时为左右）出现黑边，即用户看到的
    /// 「竖屏没有正常填满屏幕」。此处改为跟随素材比例，保证盒子与画面同形。
    static func aspectFillHeight(forWidth width: CGFloat, videoAspectRatio: CGFloat) -> CGFloat {
        let safeWidth = max(width, 0)
        guard videoAspectRatio.isFinite, videoAspectRatio > 0.01 else {
            return standardPlayerHeight(forWidth: safeWidth)
        }
        // 上限放宽到屏高的 82%：极端素材（如 4:3）也不会把播放器撑得过高，
        // 超出部分由内容区顶上去，而不是压掉底部可滚动空间。
        return max(min(safeWidth / videoAspectRatio, safeWidth * 4), 1)
    }

    static func minimumPlayerHeight(
        forWidth width: CGFloat,
        isPlaybackActive: Bool
    ) -> CGFloat {
        isPlaybackActive
            ? standardPlayerHeight(forWidth: width)
            : collapsedToolbarHeight
    }

    static func resolvedPlayerHeight(
        bounds: CGSize,
        videoAspectRatio: CGFloat,
        currentPlayerHeight: CGFloat?,
        isPlaybackActive: Bool
    ) -> CGFloat {
        let expanded = expandedPlayerHeight(
            bounds: bounds,
            videoAspectRatio: videoAspectRatio
        )
        let minimum = minimumPlayerHeight(
            forWidth: bounds.width,
            isPlaybackActive: isPlaybackActive
        )
        return max(minimum, min(currentPlayerHeight ?? expanded, expanded))
    }

    static func resolve(
        bounds: CGRect,
        safeAreaTop: CGFloat,
        videoAspectRatio: CGFloat,
        currentPlayerHeight: CGFloat?,
        isPlaybackActive: Bool,
        isLandscape: Bool,
        isPortraitFullscreen: Bool
    ) -> Self {
        let usesFullscreenLayout = isLandscape || isPortraitFullscreen
        let canInteractivelyCollapse = supportsInteractiveCollapse(
            videoAspectRatio: videoAspectRatio,
            isPlaybackActive: isPlaybackActive
        )
        let playerHeight =
            usesFullscreenLayout
            ? bounds.height
            : resolvedPlayerHeight(
                bounds: bounds.size,
                videoAspectRatio: videoAspectRatio,
                currentPlayerHeight: currentPlayerHeight,
                isPlaybackActive: isPlaybackActive
            )
        if usesFullscreenLayout {
            return Self(
                playerFrame: bounds,
                contentFrame: CGRect(
                    x: bounds.minX,
                    y: bounds.maxY,
                    width: bounds.width,
                    height: max(bounds.height, 1)
                ),
                contentTopInset: nil,
                usesFullscreenLayout: true
            )
        }

        return Self(
            playerFrame: CGRect(
                x: bounds.minX,
                y: bounds.minY + max(0, safeAreaTop),
                width: bounds.width,
                height: max(playerHeight, 0)
            ),
            contentFrame: CGRect(
                x: bounds.minX,
                y: bounds.minY + max(0, safeAreaTop),
                width: bounds.width,
                height: max(bounds.height - max(0, safeAreaTop), 0)
            ),
            contentTopInset: canInteractivelyCollapse
                ? expandedPlayerHeight(
                    bounds: bounds.size,
                    videoAspectRatio: videoAspectRatio
                )
                : max(playerHeight, 0),
            usesFullscreenLayout: false
        )
    }
}

@MainActor
struct VideoDetailInteractiveScrollMetrics: Equatable {
    let scrollOffset: CGFloat
    let collapseOffset: CGFloat
    let contentOffset: CGFloat
    let collapseDistance: CGFloat

    init(
        scrollOffset: CGFloat,
        expandedPlayerHeight: CGFloat,
        minimumPlayerHeight: CGFloat
    ) {
        let normalizedScrollOffset = max(scrollOffset, 0)
        let expandedHeight = max(expandedPlayerHeight, 0)
        let minimumHeight = min(max(minimumPlayerHeight, 0), expandedHeight)
        let distance = max(expandedHeight - minimumHeight, 0)
        self.scrollOffset = normalizedScrollOffset
        collapseOffset = min(normalizedScrollOffset, distance)
        contentOffset = max(normalizedScrollOffset - distance, 0)
        collapseDistance = distance
    }

    var isPlayerCollapsed: Bool {
        collapseOffset >= collapseDistance - 0.5
    }
}
