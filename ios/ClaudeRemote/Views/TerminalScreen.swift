import SwiftUI
import SwiftTerm

struct TerminalScreen: UIViewRepresentable {
    let onInput: (Data) -> Void
    let onResize: (Int, Int) -> Void
    /// 推送模式桥接：makeUIView 时把 terminalView 弱引用挂到 bridge 上，
    /// 之后 TerminalSession.onOutput → bridge.feed → terminalView.feed 直达，
    /// 不再靠 SwiftUI 重渲染或 layoutSubviews 主动 drain。
    let outputBridge: TerminalOutputBridge

    func makeUIView(context: Context) -> LocalTerminalView {
        let tv = LocalTerminalView()
        tv.terminalDelegate = context.coordinator
        outputBridge.terminalView = tv
        return tv
    }

    func updateUIView(_ uiView: LocalTerminalView, context: Context) {
        // 推送模式下，output 由 TerminalOutputBridge.feed 直接推送，
        // 这里不做任何 feed 操作，避免重复 feed 导致重影。
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let onInput: (Data) -> Void
        let onResize: (Int, Int) -> Void

        init(onInput: @escaping (Data) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.onInput = onInput
            self.onResize = onResize
        }

        // 协议必需方法：用户键盘输入转发给 bridge。data 是 ArraySlice<UInt8>。
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            onInput(Data(data))
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onResize(newCols, newRows)
        }
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        // 协议其余必需方法：当前不需要处理，给空实现以满足协议一致性。
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        // OSC 52 剪贴板相关：远端 Claude Code 不需要操作本机剪贴板，给空/nil 实现。
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    }
}

/// 子类：参照 SwiftTerm 官方 SwiftUITerminalHostView 实现，在 layoutSubviews
/// 里检测 bounds 变化并调 processSizeChange，让 SwiftTerm 重新计算 cols/rows
/// 并触发 sizeChanged 回调。这是 SwiftUI 集成的关键——不加这个，键盘弹起、
/// 旋转、VStack 压缩等 frame 变化时 SwiftTerm 不知道尺寸变了，还按旧尺寸渲染，
/// 导致内容错位、重影、残留、输入框/图标重复等问题。
final class LocalTerminalView: TerminalView {
    private var lastAppliedSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSizeIfNeeded()
    }

    private func updateSizeIfNeeded() {
        let newSize = bounds.size
        // 忽略 zero / 无效尺寸（SwiftUI 初始化时可能传 zero）。
        guard newSize.width.isFinite, newSize.width > 0,
              newSize.height.isFinite, newSize.height > 0 else {
            return
        }
        // 只在尺寸真正变化时才通知 SwiftTerm，避免每帧重复处理。
        if newSize != lastAppliedSize {
            lastAppliedSize = newSize
            // processSizeChange 是 TerminalView 父类方法：重算 cols/rows，
            // 更新内部 buffer，触发 sizeChanged 回调 → onResize → bridge → claude。
            processSizeChange(newSize: newSize)
        }
    }
}
