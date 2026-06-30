import SwiftUI

@main
struct ClaudeRemoteApp: App {
    @StateObject private var session = TerminalSession()

    var body: some Scene {
        WindowGroup {
            MainView(session: session)
                .onAppear { session.start() }
        }
    }
}
