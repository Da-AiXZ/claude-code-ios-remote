import SwiftUI
import SwiftTerm

struct TerminalScreen: UIViewRepresentable {
    let onInput: (Data) -> Void
    let onResize: (Int, Int) -> Void
    /// 推送模式桥接：makeUIView 时把 terminalView 弱引用挂到 bridge 上，
    /// 之后 TerminalSession.onOutput → bridge.feed → terminalView.feed 直达。
    let outputBridge: TerminalOutputBridge

    func makeUIView(context: Context) -> LocalTerminalView {
        let tv = LocalTerminalView()
        tv.terminalDelegate = context.coordinator
        // 品牌深色终端背景（#141413）+ 浅色前景（#faf9f5）
        tv.backgroundColor = UIColor(Color.brandDark)
        tv.foregroundColor = UIColor(Color.brandLight)
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
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    }
}

/// 空子类：SwiftTerm 的 TerminalView 父类 layoutSubviews 已自己处理 bounds 变化
///（检测 sizeChanged → 调 processSizeChange → setNeedsDisplay），子类不需要重写。
/// 唯一扩展：didMoveToWindow 时尝试启用 Metal GPU 渲染——这是修复渲染问题的关键。
final class LocalTerminalView: TerminalView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        // view 加到 window 后尝试启用 Metal GPU 渲染。
        // SwiftTerm 默认用 CoreGraphics（CPU 渲染）。CoreGraphics 在 iOS 16 上可能有
        // 渲染残留/重影/滑动重叠/输入框重复等问题（setNeedsDisplay 时机或不完全 invalidate）。
        // Metal 用 GPU 渲染（纹理图集 + GPU quad），避免 CoreGraphics 的渲染状态不一致问题。
        // 失败则 fallback 到 CoreGraphics（SwiftTerm 自动继续，无需处理）。
        if window != nil && !isUsingMetalRenderer {
            do {
                try setUseMetal(true)
            } catch {
                // Metal 不可用（旧设备/模拟器），静默 fallback 到 CoreGraphics。
                print("[TerminalScreen] Metal unavailable, fallback to CoreGraphics: \(error)")
            }
        }
    }
}
