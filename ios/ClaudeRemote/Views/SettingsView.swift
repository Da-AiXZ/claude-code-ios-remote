import SwiftUI

struct SettingsView: View {
    @Binding var port: Int
    @Binding var fontSize: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    Stepper(value: $port, in: 1024...65535) {
                        Text("端口：\(port)")
                    }
                }
                Section("终端") {
                    Slider(value: $fontSize, in: 9...20) {
                        Text("字体大小")
                    }
                    Text(String(format: "%.0f pt", fontSize))
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
