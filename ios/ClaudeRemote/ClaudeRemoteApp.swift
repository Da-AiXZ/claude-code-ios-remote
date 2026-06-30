import SwiftUI

@main
struct ClaudeRemoteApp: App {
    @StateObject private var session = TerminalSession()
    /// 推送模式桥接：app 级持有，terminalView 弱引用挂这里，
    /// session.onOutput → bridge.feed → terminalView.feed 直达。
    private let outputBridge = TerminalOutputBridge()

    var body: some Scene {
        WindowGroup {
            MainView(session: session, outputBridge: outputBridge)
                .onAppear {
                    // 注入推送回调：PTY output 一到（已在主线程）直接 feed 给 terminalView。
                    session.onOutput = { [weak outputBridge] data in
                        outputBridge?.feed(data)
                    }
                    session.start()
                }
        }
    }
}
