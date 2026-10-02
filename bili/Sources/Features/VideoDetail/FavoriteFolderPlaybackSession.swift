import Foundation

/// 收藏夹「播放全部」的队列会话。
///
/// `VideoDetailViewModel` 是页面级对象，随详情页创建与销毁；收藏夹页点「播放全部」
/// 时队列已经拉好，但详情页要等点击后才会创建。因此把待播队列暂存在这里，
/// 由详情页在初始化时取走并灌进 `videoListenQueueSession`。
///
/// 一次性消费：取走即失效，避免上一次播放残留的队列影响后续单视频播放。
@MainActor
final class FavoriteFolderPlaybackSession {
    static let shared = FavoriteFolderPlaybackSession()

    private(set) var pendingSeed: VideoItem?
    private(set) var pendingVideos: [VideoItem] = []
    private(set) var pendingFolderID: Int?

    private init() {}

    var hasPendingQueue: Bool {
        pendingSeed != nil && !pendingVideos.isEmpty
    }

    func stage(folderID: Int, seed: VideoItem, videos: [VideoItem]) {
        pendingFolderID = folderID
        pendingSeed = seed
        pendingVideos = videos
    }

    /// 取出并清空待播队列。
    func take(folderID: Int, seed: VideoItem) -> [VideoItem]? {
        guard hasPendingQueue,
              let pendingFolderID,
              pendingFolderID == folderID,
              let pendingSeed,
              VideoListenQueueBuilder.representsSameVideo(pendingSeed, seed)
        else { return nil }

        let videos = pendingVideos
        clear()
        return videos
    }

    func clear() {
        pendingSeed = nil
        pendingVideos = []
        pendingFolderID = nil
    }
}
