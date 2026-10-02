//
//  NavigationStackCompat.swift
//  bili
//
//  iOS 16 的 NavigationStack 一整套（NavigationPath + navigationDestination(for:)
//  + NavigationLink(value:)）在 iOS 15 上没有对应物。iOS 15 只有 NavigationView
//  和 NavigationLink(destination:) / NavigationLink(destination:isActive:)。
//
//  这里在 iOS 15 上用 NavigationView + NavigationLink(isActive:) 模拟这套数据驱动
//  的栈导航，思路是：
//
//   1. NavigationPath 自己实现，存 [AnyHashable]；
//   2. navigationDestination(for:) 把「类型 -> 视图构造器」注册进一张全局表；
//   3. NavigationStack 内部按 path.count 逐层套 NavigationLink(isActive:)，
//      Binding 的 get 用 index < path.count，set 时把多余的层 pop 掉；
//   4. NavigationLink(value:) 退化为一个往 path 里 append 的 Button。
//
//  注意：这份实现未经真机验证，行为细节（尤其是 pop 的层级同步、导航栏外观）
//  与系统原生 NavigationStack 并不一致，需要在真机上反复调。

import SwiftUI

// MARK: - NavigationPath (iOS 16)

public struct NavigationPath {
    private var elements: [AnyHashable]

    public init() {
        elements = []
    }

    public init(_ elements: [AnyHashable]) {
        self.elements = elements
    }

    public var count: Int { elements.count }
    public var isEmpty: Bool { elements.isEmpty }

    public mutating func append<V: Hashable>(_ value: V) {
        elements.append(AnyHashable(value))
    }

    public mutating func removeLast(_ k: Int = 1) {
        guard k > 0 else { return }
        elements.removeLast(min(k, elements.count))
    }

    public func element(at index: Int) -> AnyHashable? {
        guard index >= 0, index < elements.count else { return nil }
        return elements[index]
    }
}

extension NavigationPath: Equatable {
    public static func == (lhs: NavigationPath, rhs: NavigationPath) -> Bool {
        lhs.elements == rhs.elements
    }
}

// MARK: - destination 注册中心

enum NavigationDestinationRegistry {
    private static var builders: [ObjectIdentifier: (AnyHashable) -> AnyView] = [:]

    static func register<D: Hashable>(_ type: D.Type, builder: @escaping (D) -> AnyView) {
        builders[ObjectIdentifier(type)] = { any in
            guard let value = any.base as? D else { return AnyView(EmptyView()) }
            return builder(value)
        }
    }

    static func view(for value: AnyHashable) -> AnyView {
        guard let builder = builders[ObjectIdentifier(type(of: value.base))] else {
            return AnyView(EmptyView())
        }
        return builder(value)
    }
}

private struct NavigationDestinationModifier<D: Hashable, Destination: View>: ViewModifier {
    let destination: (D) -> Destination

    init(for type: D.Type, @ViewBuilder destination: @escaping (D) -> Destination) {
        self.destination = destination
        NavigationDestinationRegistry.register(type) { value in
            AnyView(destination(value))
        }
    }

    func body(content: Content) -> some View { content }
}

extension View {
    public func navigationDestination<D: Hashable, Destination: View>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> Destination
    ) -> some View {
        modifier(NavigationDestinationModifier(for: data, destination: destination))
    }
}

// MARK: - path 绑定通过环境向下传递

struct NavigationPathBindingKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationPath> = .constant(NavigationPath())
}

extension EnvironmentValues {
    var navigationPathBinding: Binding<NavigationPath> {
        get { self[NavigationPathBindingKey.self] }
        set { self[NavigationPathBindingKey.self] = newValue }
    }
}

// MARK: - 逐层递归渲染

private struct NavigationStackNode: View {
    @Binding var path: NavigationPath
    let index: Int
    let root: AnyView

    var body: some View {
        currentContent
            .background(pushLink)
    }

    private var currentContent: AnyView {
        guard index >= 0 else { return root }
        guard let element = path.element(at: index) else { return AnyView(EmptyView()) }
        return NavigationDestinationRegistry.view(for: element)
    }

    private var pushLink: some View {
        NavigationLink(
            isActive: Binding(
                get: { index + 1 < path.count },
                set: { active in
                    guard !active, index + 1 < path.count else { return }
                    path.removeLast(path.count - (index + 1))
                }
            )
        ) {
            NavigationStackNode(path: $path, index: index + 1, root: root)
        } label: {
            EmptyView()
        }
        .frame(width: 0, height: 0)
        .hidden()
    }
}

// MARK: - NavigationStack (iOS 16)

public struct NavigationStack<Root: View>: View {
    @Binding private var path: NavigationPath
    private let root: Root

    public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) {
        self._path = path
        self.root = root()
    }

    public init(@ViewBuilder root: () -> Root) {
        self._path = .constant(NavigationPath())
        self.root = root()
    }

    public var body: some View {
        NavigationView {
            NavigationStackNode(path: $path, index: -1, root: AnyView(root))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .environment(\.navigationPathBinding, $path)
    }
}

// MARK: - NavigationLink（同时覆盖 value: 与 destination: 两种写法）

public struct NavigationLink<Label: View>: View {
    private enum Kind {
        case value(AnyHashable?)
        case destination(AnyView)
    }

    private let kind: Kind
    private let label: Label

    @Environment(\.navigationPathBinding) private var pathBinding
    @State private var isActive = false

    public init<V: Hashable>(value: V?, @ViewBuilder label: () -> Label) {
        self.kind = .value(value.map { AnyHashable($0) })
        self.label = label()
    }

    public init<Destination: View>(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.kind = .destination(AnyView(destination()))
        self.label = label()
    }

    public var body: some View {
        switch kind {
        case .value(let value):
            Button {
                guard let value else { return }
                pathBinding.wrappedValue.append(value)
            } label: {
                label
            }
            .buttonStyle(.plain)

        case .destination(let destination):
            label
                .background(
                    NavigationLink(isActive: $isActive) {
                        destination
                    } label: {
                        EmptyView()
                    }
                    .frame(width: 0, height: 0)
                    .hidden()
                )
                .onTapGesture { isActive = true }
        }
    }
}
