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
        // 排空待处理字节
        while let chunk = feed() {
            uiView.feed(byteArray: Array(chunk))
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

        func send(_ source: TerminalView, data: [UInt8]) {
            onInput(Data(data))
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onResize(newCols, newRows)
        }
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}

/// 子类：暴露 feed buffer 给 SwiftUI 更新使用。
final class LocalTerminalView: TerminalView {
    var feedBuffer: (() -> Data?)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if let feed = feedBuffer {
            while let chunk = feed() {
                self.feed(byteArray: Array(chunk))
            }
        }
    }
}
