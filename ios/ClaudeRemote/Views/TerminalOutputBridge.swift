import Foundation
import SwiftTerm

/// iOS-only 桥接：把 TerminalSession（跨平台，不能 import UIKit）的 output 字节
/// 直接推送给 UIKit 的 TerminalView。用「推送模式」而非「拉模式」：
/// PTY output 一到就调 terminalView.feed(byteArray:)，不经过 SwiftUI 重渲染中转，
/// 避免重复 feed、时机错位、残留重影等问题。
final class TerminalOutputBridge {
    /// 弱引用：bridge 不持有 terminalView，避免循环引用。
    /// terminalView 由 SwiftUI 的 UIViewRepresentable 管理 lifecycle。
    weak var terminalView: LocalTerminalView?

    /// 由 TerminalSession.onOutput 调用。调用方保证在主线程（TerminalServer 的
    /// onMessage 已 dispatch 到 main）。
    func feed(_ data: Data) {
        guard let tv = terminalView else { return }
        // SwiftTerm 的 feed(byteArray:) 期望 ArraySlice<UInt8>，会增量解析并触发重绘。
        tv.feed(byteArray: ArraySlice(data))
    }

    /// bridge 重连或 session 重启时清空终端历史，避免旧内容残留。
    /// SwiftTerm 的 TerminalView 没有公开的 clear() 方法，
    /// 通过 feed ANSI 清屏序列实现：ESC[2J（清整屏）+ ESC[H（光标归位）。
    func clear() {
        // 0x1b = ESC, [2J = 清屏, [H = 光标移动到 0,0
        let clearSeq: [UInt8] = [0x1b, 0x5b, 0x32, 0x4a, 0x1b, 0x5b, 0x48]
        terminalView?.feed(byteArray: ArraySlice(clearSeq))
    }
}
