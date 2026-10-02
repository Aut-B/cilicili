import Foundation

/// 收藏夹内视频的自定义顺序覆盖层。
///
/// B 站服务端不保存收藏夹内的自定义顺序（`/x/v3/fav/resource/list` 的 `order`
/// 只接受 `mtime` / `view` / `pubtime` 三个固定预设值），因此顺序只存在于本机。
/// 跨设备同步走 `FavoriteFolderOrderTransfer` 的导出 / 导入。
nonisolated struct FavoriteFolderOrderStore: Codable, Hashable, Sendable {
    /// 收藏夹 ID → 该收藏夹内的视频顺序（存 BV 号，跨分页稳定且天然去重）。
    var folderOrders: [Int: [String]]

    init(folderOrders: [Int: [String]] = [:]) {
        self.folderOrders = folderOrders
    }

    func orderedVideoIDs(for folderID: Int) -> [String] {
        folderOrders[folderID] ?? []
    }

    mutating func setOrderedVideoIDs(_ videoIDs: [String], for folderID: Int) {
        if videoIDs.isEmpty {
            folderOrders.removeValue(forKey: folderID)
        } else {
            folderOrders[folderID] = videoIDs
        }
    }

    /// 把自定义顺序套用到收藏夹条目上。
    ///
    /// 未收录在自定义顺序里的条目不会丢失，按原顺序追加到末尾——服务端新增视频、
    /// 或用户只在部分页里拖动过顺序时都不至于让内容凭空消失。
    func applyingOrder(
        to entries: [AccountVideoEntry],
        folderID: Int
    ) -> [AccountVideoEntry] {
        let orderedVideoIDs = orderedVideoIDs(for: folderID)
        guard !orderedVideoIDs.isEmpty else { return entries }

        var remaining = Dictionary(
            entries.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var result = [AccountVideoEntry]()
        result.reserveCapacity(entries.count)

        for videoID in orderedVideoIDs {
            guard let match = remaining.removeValue(forKey: videoID) else { continue }
            result.append(match)
        }
        for entry in entries where remaining[entry.id] != nil {
            result.append(entry)
        }
        return result
    }
}

/// 收藏夹顺序的导出 / 导入载荷。
///
/// B 站不提供收藏夹内顺序的写入接口，跨设备同步只能靠用户手动搬运这份数据。
nonisolated struct FavoriteFolderOrderTransfer: Codable, Hashable, Sendable {
    /// 格式版本，留作将来字段扩展的兼容余地。
    var version: Int
    var folders: [Folder]

    struct Folder: Codable, Hashable, Sendable {
        var id: Int
        var videoIDs: [String]
    }

    init(version: Int = 1, folders: [Folder] = []) {
        self.version = version
        self.folders = folders
    }

    init(store: FavoriteFolderOrderStore) {
        self.version = 1
        self.folders = store.folderOrders
            .map { Folder(id: $0.key, videoIDs: $0.value) }
            .sorted { $0.id < $1.id }
    }

    func makeStore() -> FavoriteFolderOrderStore {
        var store = FavoriteFolderOrderStore()
        for folder in folders {
            // 同一收藏夹出现重复行时取并集，保证导入不会漏条目。
            let existing = store.orderedVideoIDs(for: folder.id)
            var seen = Set(existing)
            store.setOrderedVideoIDs(
                existing + folder.videoIDs.filter { seen.insert($0).inserted },
                for: folder.id
            )
        }
        return store
    }
}
