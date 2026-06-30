import SwiftUI
import SwiftTerm

struct TerminalScreen: UIViewRepresentable {
    let onInput: (Data) -> Void
    let onResize: (Int, Int) -> Void
    let feed: () -> Data?  // 返回自上次调用以来待投喂的字节

    func makeUIView(context: Context) -> LocalTerminalView {
        let tv = LocalTerminalView()
        tv.terminalDelegate = context.coordinator
        tv.feedBuffer = feed
        return tv
    }

    func updateUIView(_ uiView: LocalTerminalView, context: Context) {
        // 排空待处理字节。SwiftTerm 的 feed(byteArray:) 期望 ArraySlice<UInt8>。
        while let chunk = feed() {
            uiView.feed(byteArray: ArraySlice(chunk))
        }
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

/// 子类：暴露 feed buffer 给 SwiftUI 更新使用。
final class LocalTerminalView: TerminalView {
    var feedBuffer: (() -> Data?)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let feed = feedBuffer {
            while let chunk = feed() {
                self.feed(byteArray: ArraySlice(chunk))
            }
        }
    }
}
