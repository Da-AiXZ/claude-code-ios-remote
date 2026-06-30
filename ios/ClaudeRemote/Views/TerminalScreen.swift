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

/// 子类：纯粹作为 TerminalView 的具体类型用（SwiftTerm 的 feed/clear 等方法在父类已实现）。
/// 不再重写 layoutSubviews 做 feed——推送模式下 output 由 TerminalOutputBridge 直接推送。
final class LocalTerminalView: TerminalView {}
