import SwiftUI

struct KeyboardAccessory: View {
    let onKey: (String) -> Void

    private let keys: [(label: String, sends: String)] = [
        ("ESC", "\u{1B}"),
        ("TAB", "\t"),
        ("CTRL", "\u{1}"),      // 哨兵值 —— 由 coordinator 切换 ctrl 模式处理
        ("↑", "\u{1B}[A"),
        ("↓", "\u{1B}[B"),
        ("←", "\u{1B}[D"),
        ("→", "\u{1B}[C"),
        ("HOME", "\u{1B}[H"),
        ("END", "\u{1B}[F"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys.indices, id: \.self) { idx in
                Button(keys[idx].label) { onKey(keys[idx].sends) }
                    .buttonStyle(KeyButtonStyle())
            }
            Spacer()
            Button("/") { onKey("/") }
                .buttonStyle(KeyButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
    }
}

private struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.accentColor.opacity(0.4) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}
