import SwiftUI

struct VideoDetailToolbarSegmentedPickerView: View {
    static let compactWidth: CGFloat = 132
    /// 切换器高度。iOS 15 上它被包进回退底栏，过于扁平会挤字、过高则吃掉竖屏可视区，
    /// 故取 32pt：既保证可点区域，也把底栏总高控制在 40pt 上下。
    static let height: CGFloat = 32

    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: VideoDetailContentTab
    @Namespace private var selectionIndicatorNamespace

    var body: some View {
        HStack(spacing: 0) {
            segment(title: "简介", tab: .detail)
            segment(title: "评论", tab: .comments)
        }
        .frame(width: Self.compactWidth, height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("内容")
        .accessibilityIdentifier("video.detail.toolbar-picker")
        .animation(.smooth(duration: 0.22), value: selection)
    }

    private func segment(title: String, tab: VideoDetailContentTab) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.22)) {
                selection = tab
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Capsule())
                .background {
                    if selection == tab {
                        Capsule()
                            .fill(selectionFill)
                            .overlay {
                                Capsule()
                                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                            .matchedGeometryEffect(
                                id: "video-detail-toolbar-selection",
                                in: selectionIndicatorNamespace
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selection == tab ? "已选中" : "未选中")
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    private var selectionFill: Color {
        colorScheme == .light ? .white.opacity(0.75) : .primary.opacity(0.14)
    }
}

private struct VideoDetailToolbarSegmentedPickerPreview: View {
    @State private var selection: VideoDetailContentTab = .detail

    var body: some View {
        VideoDetailToolbarSegmentedPickerView(selection: $selection)
            .frame(width: VideoDetailToolbarSegmentedPickerView.compactWidth)
    }
}

#Preview("视频详情底部切换器") {
    VideoDetailToolbarSegmentedPickerPreview()
}
