import Foundation
import Combine

final class TerminalSession: ObservableObject {
    @Published var status: String = "idle"
}
