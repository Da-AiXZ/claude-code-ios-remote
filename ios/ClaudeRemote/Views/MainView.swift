import SwiftUI
import SwiftTerm

struct MainView: View {
    @ObservedObject var session: TerminalSession
    /// 推送模式桥接：terminalView 弱引用挂这里，session.onOutput → bridge.feed 直达。
    let outputBridge: TerminalOutputBridge
    @AppStorage("claudeRemote.port") private var portSetting: Int = 8080
    @AppStorage("claudeRemote.fontSize") private var fontSize: Double = 13
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ConnectionInfoView(session: session)
                .padding(.horizontal)
                .padding(.top, 8)

            // Terminal 占满中间剩余空间。不去 ignoresSafeArea(.keyboard)：
            // 键盘弹起时 SwiftUI 自动压缩 terminal 高度，sizeChanged → onResize →
            // bridge → claude 同步新 cols/rows，对端按新尺寸输出，不再错位。
            TerminalScreen(
                onInput: { data in session.sendInput(data) },
                onResize: { cols, rows in session.sendResize(cols: cols, rows: rows) },
                outputBridge: outputBridge
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
