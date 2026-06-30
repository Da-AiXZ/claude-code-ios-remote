import SwiftUI

struct ConnectionInfoView: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text(session.statusText)
                    .font(.brandBody(14))
                    .foregroundColor(.brandLight)
            }
            if case .listening(let addr) = session.phase {
                Label("Bridge 命令", systemImage: "terminal")
                    .font(.brandTitle(12))
                    .foregroundColor(.brandMidGray)
                Text("node bridge.js \(addr)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundColor(.brandLightGray)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.brandLightGray.opacity(0.08))
        )
    }

    private var statusIcon: String {
        switch session.phase {
        case .idle: return "circle.dashed"
        case .starting: return "arrow.triangle.2.circlepath"
        case .listening: return "wifi"
        case .running: return "checkmark.circle.fill"
        case .exited: return "arrow.uturn.backward.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .running: return .brandGreen
        case .failed: return .brandOrange
        case .exited: return .brandOrange
        default: return .brandBlue
        }
    }
}
