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

            TerminalScreen(
                onInput: { data in session.sendInput(data) },
                onResize: { cols, rows in session.sendResize(cols: cols, rows: rows) },
                feed: { session.drainPendingBytes() }
            )
            .ignoresSafeArea(.keyboard)

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
