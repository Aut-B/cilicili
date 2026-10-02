import SwiftUI
import UIKit

struct VideoDetailInitialPlaybackLayout {
    let width: CGFloat
    let playerHeight: CGFloat

    init(proxy: GeometryProxy, isPortraitVideo: Bool) {
        let fullscreenSize = proxy.fullscreenContainerGeometry.size
        width = PlaybackDetailStableLayout.portraitWidth(
            containerSize: proxy.size,
            fullscreenSize: fullscreenSize,
            windowSize: UIApplication.shared.playbackDetailForegroundKeyWindow?.bounds.size
        )

        let standardHeight = PlaybackDetailPlayerMetrics.standardHeight(for: width)
        if isPortraitVideo {
            let proposedHeight = max(proxy.size.height * 0.65, width)
            let maximumHeight = max(standardHeight, proxy.size.height * 0.72)
            playerHeight = max(standardHeight, min(proposedHeight, maximumHeight))
        } else {
            // 横屏素材在竖屏下按真实比例撑满宽度，避免 `.resizeAspect` 在固定
            // 9:16 盒子里留黑边（与 VideoDetailShellLayout.aspectFillHeight 保持一致，
            // 否则首帧与后续布局不一致会出现一次高度跳变）。
            playerHeight = VideoDetailShellLayout.aspectFillHeight(
                forWidth: width,
                videoAspectRatio: 16.0 / 9.0
            )
        }
    }
}
