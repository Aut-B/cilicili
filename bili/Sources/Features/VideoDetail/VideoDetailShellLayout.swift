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

    /// 判定「竖直拍摄素材」的宽高比阈值。
    ///
    /// 旧实现用 `0.9` 且**没有校验宽高比是否缺失**：元数据尚未加载完成时
    /// `videoAspectRatio` 为 0，而 `0 < 0.9` 成立，于是 16:9 素材被误判为竖屏素材，
    /// 返回 `bounds.height * 0.65`（iPhone 6s 上约 433pt）的高盒子。画面在
    /// `.resizeAspect` 下居中后上下各留约 111pt 黑边，即用户反馈的
    /// 「竖屏没有正常填满屏幕、上方空出大黑边」。阈值收紧到 0.8（真正的竖直素材
    /// 宽高比通常在 0.5625 左右，0.8 足以区分，且不再误伤 4:3 等横向素材）。
    static let portraitAspectRatioThreshold: CGFloat = 0.8

    /// 归一化宽高比：缺失、非有限值或超出合理区间时一律回退到 16:9。
    ///
    /// 关键点：**宽高比未知必须按横屏素材处理，而不是按竖屏素材处理**，
    /// 否则会走进 0.65 屏高的高盒子分支产生黑边。
    static func normalizedAspectRatio(_ raw: CGFloat) -> CGFloat {
        guard raw.isFinite, raw > 0.2 else { return 16.0 / 9.0 }
        return min(max(raw, 0.2), 4.0)
    }

    static func expandedPlayerHeight(
        bounds: CGSize,
        videoAspectRatio: CGFloat
    ) -> CGFloat {
        let ratio = normalizedAspectRatio(videoAspectRatio)
        let standard = standardPlayerHeight(forWidth: bounds.width)
        guard ratio < portraitAspectRatioThreshold else {
            // 横屏素材：宽度铺满、盒子比例跟随素材，`.resizeAspect` 不再产生上下黑边。
            // 上限收敛到 0.72 屏高，避免极端素材（超宽/超高）把播放器撑得过高。
            return min(
                aspectFillHeight(forWidth: bounds.width, videoAspectRatio: ratio),
                max(standard, bounds.height * 0.72)
            )
        }
        // 竖直拍摄素材：给一个更高的观看区（宽度仍铺满）。
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
