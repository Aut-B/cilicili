//
//  iOS15CompatSystem.swift
//  bili
//
//  第二批 iOS 15 兼容层：覆盖首轮 CI 报出的 417 个编译错误中的大部分。
//
//  两类手法：
//   1. SwiftUI 侧：本模块同名类型 / 同签名扩展遮蔽 iOS 16+ 接口（调用点不改）；
//   2. 系统侧（UIKit / AVKit / Swift 标准库）：这些是系统类型的成员，无法用同名类型
//      遮蔽，只能在扩展里补一个同签名成员作为降级实现——能编译、语义退化，但至少
//      不会崩。凡是「补了也没意义」的（如 iOS 26 液态玻璃、HDR 色调映射），
//      一律做成空操作。
//
//  注意：这批代码只经过 GitHub Actions 上的编译验证，未做真机行为验证。

import SwiftUI
import UIKit
import AVKit
import PhotosUI

// MARK: - onChange(of:initial:_:) (iOS 17，71 处)

private struct OnChangeInitialModifier<V: Equatable>: ViewModifier {
    let value: V
    let initial: Bool
    let action: (V, V) -> Void

    @State private var previous: V?

    func body(content: Content) -> some View {
        content
            .onAppear {
                if previous == nil {
                    previous = value
                    if initial {
                        action(value, value)
                    }
                }
            }
            .onChange(of: value) { newValue in
                let old = previous ?? newValue
                previous = newValue
                action(old, newValue)
            }
    }
}

extension View {
    // initial 必须带默认值：调用点普遍写作 .onChange(of: x) { _, _ in }，
    // 命中 iOS 17 那个 initial 有默认值的重载。
    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping (V, V) -> Void
    ) -> some View {
        modifier(OnChangeInitialModifier(value: value, initial: initial, action: action))
    }

    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        modifier(
            OnChangeInitialModifier(
                value: value,
                initial: initial,
                action: { _, _ in action() }
            )
        )
    }
}

// MARK: - Duration / Task.sleep(for:) (Swift 标准库，iOS 16)

public struct Duration: Hashable, Comparable {
    public let timeInterval: TimeInterval

    private init(timeInterval: TimeInterval) { self.timeInterval = timeInterval }

    public static func seconds(_ value: Double) -> Duration {
        Duration(timeInterval: value)
    }

    public static func seconds<T: BinaryInteger>(_ value: T) -> Duration {
        Duration(timeInterval: Double(value))
    }

    public static func milliseconds(_ value: Double) -> Duration {
        Duration(timeInterval: value / 1000.0)
    }

    public static func milliseconds<T: BinaryInteger>(_ value: T) -> Duration {
        Duration(timeInterval: Double(value) / 1000.0)
    }

    public static func < (lhs: Duration, rhs: Duration) -> Bool {
        lhs.timeInterval < rhs.timeInterval
    }
}

extension Task {
    public static func sleep(for duration: Duration) async throws {
        let clamped = max(0, duration.timeInterval)
        try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
    }
}

// MARK: - URL (iOS 16)

// 不要把这个枚举嵌进 extension URL：嵌套类型放在扩展里时，
// 调用点写 URL.DirectoryHint / UIWindowScene.GeometryPreferences 会被系统那份
// （iOS 16 才有）抢先解析，结果还是报不可用。放到顶层就没这个歧义。
public enum BiliURLDirectoryHint {
    case notDirectory
    case isDirectory
    case checkFileSystem
    case inferFromPath
}

extension URL {
    public func appending(
        path: String,
        directoryHint: BiliURLDirectoryHint = .inferFromPath
    ) -> URL {
        appendingPathComponent(path, isDirectory: directoryHint == .isDirectory)
    }

    public func appending(path: String) -> URL {
        appendingPathComponent(path)
    }

    public static var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    public static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    public static var temporaryDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}

// MARK: - Toolbar 相关 (iOS 16 / 17 / 18)

public enum ToolbarPlacement: Hashable {
    case automatic
    case navigationBar
    case tabBar
    case bottomBar
    case keyboard
    case windowBar
}

public enum ToolbarTitleDisplayMode: Hashable {
    case automatic
    case inline
    case inlineLarge
    case large
}

extension View {
    public func toolbarBackground<S: ShapeStyle>(
        _ style: S,
        for bars: ToolbarPlacement
    ) -> some View {
        self
    }

    public func toolbarBackground(
        _ visibility: Visibility,
        for bars: ToolbarPlacement
    ) -> some View {
        self
    }

    public func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement) -> some View {
        self
    }

    public func toolbar<C: View>(
        @ViewBuilder content: () -> C,
        for bars: ToolbarPlacement
    ) -> some View {
        self
    }

    public func toolbarVisibility(
        _ visibility: Visibility,
        for bars: ToolbarPlacement
    ) -> some View {
        self
    }

    public func toolbarTitleDisplayMode(_ mode: ToolbarTitleDisplayMode) -> some View {
        self
    }
}

// MARK: - Scroll 相关 (iOS 16 / 17)

public enum ScrollDismissesKeyboardMode: Hashable {
    case automatic
    case immediately
    case interactively
    case never
}

extension View {
    public func scrollIndicators(
        _ visibility: Visibility,
        axes: Axis.Set = [.vertical, .horizontal]
    ) -> some View {
        self
    }

    public func scrollDisabled(_ disabled: Bool) -> some View { self }

    public func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View {
        self
    }

    public func scrollClipDisabled(_ disabled: Bool = true) -> some View { self }
}

// MARK: - contentMargins / safeAreaPadding (iOS 17)

public enum ContentMarginPlacement: Hashable {
    case automatic
    case scrollContent
    case scrollIndicators
}

extension View {
    public func contentMargins(
        _ edges: Edge.Set,
        _ length: CGFloat?,
        for placement: ContentMarginPlacement
    ) -> some View {
        self
    }

    public func contentMargins(
        _ length: CGFloat,
        for placement: ContentMarginPlacement
    ) -> some View {
        self
    }

    public func safeAreaPadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        self
    }
}

// MARK: - Form / Grid / 文本 (iOS 16 / 17)

public struct FormStyle: Hashable {
    private let identifier: String
    private init(_ identifier: String) { self.identifier = identifier }

    public static let automatic = FormStyle("automatic")
    public static let grouped = FormStyle("grouped")
    public static let columns = FormStyle("columns")
}

// 注意：ButtonBorderShape 不要自己定义。SwiftUI 的 ButtonBorderShape 在 iOS 15 上
// 已经可用，只是 .circle 这个 case 是 iOS 17 才加的——重复定义会让 .capsule 变成
// 二义引用。.circle 那处调用点单独改成 .capsule 即可。

extension View {
    public func formStyle(_ style: FormStyle) -> some View { self }
    public func gridCellColumns(_ count: Int) -> some View { self }
    public func fontWeight(_ weight: Font.Weight?) -> some View { self }
    public func lineLimit(_ limit: ClosedRange<Int>) -> some View { self }
    public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View { self }
    public func persistentSystemOverlays(_ visibility: Visibility) -> some View { self }
    public func presentationBackground<S: ShapeStyle>(_ style: S) -> some View { self }
    public func sharedBackgroundVisibility(_ visibility: Visibility) -> some View { self }
}

extension Font {
    public static func system(
        _ style: Font.TextStyle,
        design: Font.Design = .default,
        weight: Font.Weight = .regular
    ) -> Font {
        Font.system(style, design: design).weight(weight)
    }
}

extension TextField where Label == Text {
    public init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis) {
        self.init(title, text: text)
    }
}

// MARK: - 几何变化回调 (iOS 18)

extension View {
    public func onGeometryChange<T: Equatable, U: Equatable>(
        for type: T.Type,
        of transform: @escaping (T) -> U,
        action: @escaping (U) -> Void
    ) -> some View {
        self
    }

    // 源码里 action 写成 { _, viewWidth in ... }，是 (旧值, 新值) 两个参数
    public func onGeometryChange<T: Equatable, U: Equatable>(
        for type: T.Type,
        of transform: @escaping (T) -> U,
        action: @escaping (U, U) -> Void
    ) -> some View {
        self
    }

    public func onScrollGeometryChange<T: Equatable, U: Equatable>(
        for type: T.Type,
        of transform: @escaping (T) -> U,
        action: @escaping (U, U) -> Void
    ) -> some View {
        self
    }
}

// MARK: - navigationDestination(item:) (iOS 17)

extension View {
    public func navigationDestination<D: Hashable, Destination: View>(
        item: Binding<D?>,
        @ViewBuilder destination: @escaping (D) -> Destination
    ) -> some View {
        background(
            SwiftUI.NavigationLink(
                isActive: Binding(
                    get: { item.wrappedValue != nil },
                    set: { active in
                        if !active { item.wrappedValue = nil }
                    }
                ),
                destination: {
                    if let value = item.wrappedValue {
                        destination(value)
                    } else {
                        EmptyView()
                    }
                },
                label: { EmptyView() }
            )
            .frame(width: 0, height: 0)
            .hidden()
        )
    }
}

// MARK: - 液态玻璃容器 / Tab 栏 (iOS 26)

public struct GlassEffectContainer<Content: View>: View {
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View { content }
}

public enum ToolbarSpacerSizing: Hashable {
    case flexible
    case fixed
}

// sharedBackgroundVisibility 在源码里是接在 ToolbarItem(...) 后面的，接收者是 ToolbarContent
extension ToolbarContent {
    public func sharedBackgroundVisibility(_ visibility: Visibility) -> some ToolbarContent {
        self
    }
}

public struct ToolbarSpacer: ToolbarContent {
    public init(
        _ sizing: ToolbarSpacerSizing = .flexible,
        placement: ToolbarItemPlacement = .automatic
    ) {}

    public var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) { EmptyView() }
    }
}

extension View {
    public func scrollEdgeEffectStyle(
        _ style: ScrollEdgeEffectStyle?,
        for edge: Edge
    ) -> some View {
        self
    }

    public func safeAreaBar<Bar: View>(
        edge: Edge,
        alignment: Alignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Bar
    ) -> some View {
        self
    }

    public func tabViewBottomAccessory<Accessory: View>(
        isEnabled: Bool,
        @ViewBuilder content: () -> Accessory
    ) -> some View {
        self
    }
}

public struct GlassButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SwiftUI.Button { configuration.trigger() } label: { configuration.label }
    }
}

public struct GlassProminentButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SwiftUI.Button { configuration.trigger() } label: { configuration.label }
    }
}

extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    public static var glass: GlassButtonStyle { GlassButtonStyle() }
}

extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle {
    public static var glassProminent: GlassProminentButtonStyle { GlassProminentButtonStyle() }
}

// MARK: - Tab (iOS 18)

public struct Tab<Value: Hashable, Content: View, Label: View>: View {
    private let value: Value
    private let content: Content
    private let label: Label

    public init(
        value: Value,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.value = value
        self.content = content()
        self.label = label()
    }

    public init<S: StringProtocol>(
        _ title: S,
        systemImage: String,
        value: Value,
        @ViewBuilder content: () -> Content
    ) where Label == SwiftUI.Label<Text, Image> {
        self.value = value
        self.content = content()
        self.label = SwiftUI.Label(title, systemImage: systemImage)
    }

    public init<S: StringProtocol>(
        _ title: S,
        @ViewBuilder content: () -> Content
    ) where Label == Text, Value == String {
        self.value = String(title)
        self.content = content()
        self.label = Text(title)
    }

    public var body: some View {
        content
            .tabItem { label }
            .tag(value)
    }
}

// MARK: - UnevenRoundedRectangle (iOS 16)

public struct UnevenRoundedRectangle: Shape {
    public var topLeadingRadius: CGFloat
    public var bottomLeadingRadius: CGFloat
    public var bottomTrailingRadius: CGFloat
    public var topTrailingRadius: CGFloat
    public var style: RoundedCornerStyle

    public init(
        topLeadingRadius: CGFloat = 0,
        bottomLeadingRadius: CGFloat = 0,
        bottomTrailingRadius: CGFloat = 0,
        topTrailingRadius: CGFloat = 0,
        style: RoundedCornerStyle = .continuous
    ) {
        self.topLeadingRadius = topLeadingRadius
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
        self.topTrailingRadius = topTrailingRadius
        self.style = style
    }

    public func path(in rect: CGRect) -> Path {
        var corners: UIRectCorner = []
        if topLeadingRadius > 0 { corners.insert(.topLeft) }
        if topTrailingRadius > 0 { corners.insert(.topRight) }
        if bottomLeadingRadius > 0 { corners.insert(.bottomLeft) }
        if bottomTrailingRadius > 0 { corners.insert(.bottomRight) }

        let radius = max(
            max(topLeadingRadius, topTrailingRadius),
            max(bottomLeadingRadius, bottomTrailingRadius)
        )
        guard radius > 0, !corners.isEmpty else { return Path(rect) }

        let bezier = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(bezier.cgPath)
    }
}

// MARK: - ProposedViewSize (iOS 16，UIViewRepresentable 的 sizeThatFits 参数)

public struct ProposedViewSize: Equatable {
    public var width: CGFloat?
    public var height: CGFloat?

    public init(width: CGFloat? = nil, height: CGFloat? = nil) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }

    public func replacingUnspecifiedDimensions(by replacement: CGSize = .zero) -> CGSize {
        CGSize(width: width ?? replacement.width, height: height ?? replacement.height)
    }
}

// MARK: - UIKit：方向 / 几何 (iOS 16)

public struct BiliWindowSceneGeometry {
    public var interfaceOrientation: UIInterfaceOrientation { .portrait }
    public var coordinateSpace: UICoordinateSpace { UIScreen.main.coordinateSpace }
}

public struct BiliGeometryPreferences {
    public let interfaceOrientations: UIInterfaceOrientationMask

    public init(interfaceOrientations: UIInterfaceOrientationMask) {
        self.interfaceOrientations = interfaceOrientations
    }

    public static func iOS(
        interfaceOrientations: UIInterfaceOrientationMask
    ) -> BiliGeometryPreferences {
        BiliGeometryPreferences(interfaceOrientations: interfaceOrientations)
    }
}

extension UIWindowScene {
    public var effectiveGeometry: BiliWindowSceneGeometry { BiliWindowSceneGeometry() }

    public func requestGeometryUpdate(
        _ preferences: BiliGeometryPreferences,
        errorHandler: ((Error) -> Void)? = nil
    ) {}
}

extension UIViewController {
    public func setNeedsUpdateOfSupportedInterfaceOrientations() {
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

// MARK: - UIKit：Trait 系统 (iOS 17)

public struct UITraitUserInterfaceStyle {}
public struct UITraitPreferredContentSizeCategory {}

public struct BiliTraitOverrides {
    public init() {}

    public func contains<T>(_ traitType: T.Type) -> Bool { false }

    public mutating func remove<T>(_ traitType: T.Type) {}

    public var preferredContentSizeCategory: UIContentSizeCategory {
        get { .unspecified }
        set {}
    }
}

extension UIWindowScene {
    public var traitOverrides: BiliTraitOverrides {
        get { BiliTraitOverrides() }
        set {}
    }
}

extension UIViewController {
    public func registerForTraitChanges<T>(
        _ traits: [T.Type],
        handler: @escaping (Self, UITraitCollection) -> Void
    ) {}
}

// MARK: - UIKit：搜索栏 / 返回手势 / 标签栏 (iOS 16 / 18 / 26)

public enum BiliSearchBarPlacement {
    case automatic
    case stacked
    case integrated
    case integratedButton
}

extension UINavigationItem {
    public var preferredSearchBarPlacement: BiliSearchBarPlacement {
        get { .automatic }
        set {}
    }

    public var searchBarPlacementAllowsToolbarIntegration: Bool {
        get { false }
        set {}
    }
}

extension UINavigationController {
    public var interactiveContentPopGestureRecognizer: UIGestureRecognizer? { nil }
}

extension UITabBarController {
    public var isTabBarHidden: Bool {
        get { tabBar.isHidden }
        set { tabBar.isHidden = newValue }
    }

    public func setTabBarHidden(_ hidden: Bool, animated: Bool) {
        tabBar.isHidden = hidden
    }
}

// MARK: - UIKit：Hosting / 按钮 (iOS 16.4 / 26)

public struct BiliHostingSizingOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let intrinsicContentSize = BiliHostingSizingOptions(rawValue: 1 << 0)
    public static let preferredContentSize = BiliHostingSizingOptions(rawValue: 1 << 1)
}

public struct BiliSafeAreaRegions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let all = BiliSafeAreaRegions(rawValue: 1 << 0)
    public static let container = BiliSafeAreaRegions(rawValue: 1 << 1)
    public static let keyboard = BiliSafeAreaRegions(rawValue: 1 << 2)
}

extension UIHostingController {
    public var sizingOptions: BiliHostingSizingOptions {
        get { [] }
        set {}
    }

    public var safeAreaRegions: BiliSafeAreaRegions {
        get { .all }
        set {}
    }
}

extension UIButton.Configuration {
    public static func clearGlass() -> UIButton.Configuration { .plain() }
}

// MARK: - AVKit：播放速度 / HDR (iOS 16 / 18 / 26)

public struct AVPlaybackSpeed: Hashable {
    public let rate: Float
    public init(rate: Float) { self.rate = rate }

    public static let systemDefaultSpeeds: [AVPlaybackSpeed] = []
}

public enum BiliDisplayDynamicRange {
    case automatic
    case standard
    case high
    case never
}

extension AVPlayerViewController {
    public var speeds: [AVPlaybackSpeed] {
        get { [] }
        set {}
    }

    public var allowsVideoFrameAnalysis: Bool {
        get { false }
        set {}
    }

    public var preferredDisplayDynamicRange: BiliDisplayDynamicRange {
        get { .automatic }
        set {}
    }
}

extension AVPlayer {
    public var defaultRate: Float {
        get { 1.0 }
        set {}
    }
}

extension CALayer {
    public var toneMapMode: BiliDisplayDynamicRange {
        get { .automatic }
        set {}
    }

    public var preferredDynamicRange: BiliDisplayDynamicRange {
        get { .automatic }
        set {}
    }
}

// MARK: - ContentUnavailableView.search (iOS 17)

extension ContentUnavailableView where Label == Text, Description == Text, Actions == EmptyView {
    public static func search(text: String) -> ContentUnavailableView<Text, Text, EmptyView> {
        ContentUnavailableView(systemImage: "magnifyingglass") {
            Text("无搜索结果")
        } description: {
            Text(text)
        } actions: {
            EmptyView()
        }
    }
}

// MARK: - presentationDetents(_:selection:) (iOS 16)

extension View {
    public func presentationDetents(
        _ detents: [PresentationDetent],
        selection: Binding<PresentationDetent>
    ) -> some View {
        self
    }
}

// MARK: - PhotosPicker (iOS 16) —— iOS 15 上整体降级为空实现

public enum BiliPhotosPickerEncoding {
    case automatic
    case current
    case compatible
}

extension PhotosPickerItem {
    public var itemIdentifier: String? { nil }

    public func loadTransferable<T>(type: T.Type) async throws -> T? { nil }
}

extension View {
    public func photosPicker(
        isPresented: Binding<Bool>,
        selection: Binding<[PhotosPickerItem]>,
        maxSelectionCount: Int? = nil,
        matching: PHPickerFilter? = nil,
        preferredItemEncoding: BiliPhotosPickerEncoding = .current
    ) -> some View {
        self
    }
}
