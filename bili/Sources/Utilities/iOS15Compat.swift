//
//  iOS15Compat.swift
//  bili
//
//  部署目标降到 iOS 15 后，代码中大量 iOS 16/17/18 才有的 SwiftUI 接口会编译失败。
//  这里用「本模块同名类型遮蔽系统类型」的方式补上这些接口。
//
//  原理：Swift 的名称解析优先当前模块，再查导入模块。SwiftUI 里那些类型都带
//  @available(iOS 16.0, *) 之类的标记，部署目标为 iOS 15 时编译器根本不允许引用；
//  而本模块内定义的同名类型不带可用性限制，因此会被优先选中，调用点可以一行不改。
//
//  这些实现只求「能编译、能显示」，视觉细节与系统原生版本并不完全一致。

import SwiftUI

// MARK: - LabeledContent (iOS 16)

public struct LabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    public init(@ViewBuilder label: () -> Label, @ViewBuilder content: () -> Content) {
        self.label = label()
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            label
            Spacer(minLength: 12)
            content
                .multilineTextAlignment(.trailing)
        }
    }
}

extension LabeledContent where Label == Text, Content == Text {
    public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2) {
        self.init {
            Text(title)
        } content: {
            Text(value)
        }
    }
}

extension LabeledContent where Label == Text {
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.init {
            Text(title)
        } content: content
    }
}

// MARK: - ContentUnavailableView (iOS 17)

public struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    private let systemImage: String?
    private let label: Label
    private let description: Description
    private let actions: Actions

    public init(
        systemImage: String? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
            }
            label
                .font(.headline)
            description
                .font(.subheadline)
                .foregroundColor(.secondary)
            actions
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity)
    }
}

extension ContentUnavailableView where Label == Text, Description == Text?, Actions == EmptyView {
    public init(_ title: S, systemImage: String) where S: StringProtocol {
        self.init(systemImage: systemImage) {
            Text(title)
        } description: {
            Text?(nil)
        } actions: {
            EmptyView()
        }
    }

    public init(_ title: S, systemImage: String, description: Text) where S: StringProtocol {
        self.init(systemImage: systemImage) {
            Text(title)
        } description: {
            Optional(description)
        } actions: {
            EmptyView()
        }
    }
}

extension ContentUnavailableView where Description == EmptyView, Actions == EmptyView {
    public init(@ViewBuilder label: () -> Label) {
        self.init(systemImage: nil, label: label) {
            EmptyView()
        } actions: {
            EmptyView()
        }
    }
}

// MARK: - Visibility / scrollContentBackground (iOS 16)

public enum Visibility: Hashable {
    case automatic
    case visible
    case hidden
}

extension View {
    public func scrollContentBackground(_ visibility: Visibility) -> some View {
        self
    }
}

// MARK: - PresentationDetent / presentationDetents (iOS 16)

public struct PresentationDetent: Hashable {
    private let identifier: String
    private init(_ identifier: String) { self.identifier = identifier }

    public static let medium = PresentationDetent("medium")
    public static let large = PresentationDetent("large")

    public static func fraction(_ fraction: CGFloat) -> PresentationDetent {
        PresentationDetent("fraction:\(fraction)")
    }

    public static func height(_ height: CGFloat) -> PresentationDetent {
        PresentationDetent("height:\(height)")
    }
}

extension View {
    public func presentationDetents(_ detents: [PresentationDetent]) -> some View { self }
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View { self }
    public func presentationDragIndicator(_ visibility: Visibility) -> some View { self }
}

// MARK: - ScrollBounceBehavior (iOS 16.4)

public enum ScrollBounceBehavior: Hashable {
    case automatic
    case always
    case basedOnSize
}

extension View {
    public func scrollBounceBehavior(
        _ behavior: ScrollBounceBehavior,
        axes: Axis.Set = [.vertical]
    ) -> some View {
        self
    }
}

// MARK: - ContentTransition / symbolEffect (iOS 17)

public struct ContentTransition: Hashable {
    public static let identity = ContentTransition()
    public static let opacity = ContentTransition()
    public static let interpolate = ContentTransition()

    public static func numericText() -> ContentTransition { ContentTransition() }
    public static func symbolEffect(_ effect: SymbolEffect) -> ContentTransition { ContentTransition() }
    public static func symbolEffect(
        _ effect: SymbolEffect,
        options: SymbolEffectOptions
    ) -> ContentTransition { ContentTransition() }
}

public struct SymbolEffect: Hashable {
    public static let automatic = SymbolEffect()
    public static let appear = SymbolEffect()
    public static let disappear = SymbolEffect()
    public static let replace = SymbolEffect()
    public static let bounce = SymbolEffect()
    public static let pulse = SymbolEffect()
    public static let breathe = SymbolEffect()
    public static let wiggle = SymbolEffect()
    public static let rotate = SymbolEffect()
    public static let scaleUp = SymbolEffect()
    public static let scaleDown = SymbolEffect()
    public static let vanish = SymbolEffect()
}

public struct SymbolEffectOptions: Hashable {
    public static let `default` = SymbolEffectOptions()
    public static let repeating = SymbolEffectOptions()
    public static let nonRepeating = SymbolEffectOptions()
}

extension View {
    public func contentTransition(_ transition: ContentTransition) -> some View { self }
}

// MARK: - ScrollPhase / onScrollPhaseChange (iOS 18)

public struct ScrollPhase: Equatable {
    public var isScrolling: Bool { false }

    public static let idle = ScrollPhase()
    public static let interacting = ScrollPhase()
    public static let decelerating = ScrollPhase()
    public static let animating = ScrollPhase()
    public static let tracking = ScrollPhase()
}

extension View {
    public func onScrollPhaseChange(
        _ action: @escaping (ScrollPhase, ScrollPhase) -> Void
    ) -> some View {
        self
    }

    public func onScrollPhaseChange(
        _ action: @escaping (ScrollPhase) -> Void
    ) -> some View {
        self
    }
}
