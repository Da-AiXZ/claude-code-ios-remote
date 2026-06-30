import SwiftUI
import SwiftTerm

struct MainView: View {
    @ObservedObject var session: TerminalSession
    @AppStorage("claudeRemote.port") private var portSetting: Int = 8080
    @AppStorage("claudeRemote.fontSize") private var fontSize: Double = 13
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ConnectionInfoView(session: session)
                .padding(.horizontal)
                .padding(.top, 8)

            // Terminal 占满中间剩余空间。不去 ignoresSafeArea(.keyboard)：
            // 键盘弹起时 SwiftUI 会自动压缩 terminal 高度，terminal 内容滚动到可见区，
            // 避免被键盘遮挡导致新旧帧重叠（重影）。KeyboardAccessory 作为输入辅助条
            // 贴在 VStack 底部，键盘弹起时它会跟随键盘一起上移。
            TerminalScreen(
                onInput: { data in session.sendInput(data) },
                onResize: { cols, rows in session.sendResize(cols: cols, rows: rows) },
                feed: { session.drainPendingBytes() }
            )

            KeyboardAccessory(onKey: { seq in
                session.sendInput(seq.data(using: .utf8) ?? Data())
            })
        }
        .navigationTitle("ClaudeRemote")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(port: $portSetting, fontSize: $fontSize)
        }
    }
}
