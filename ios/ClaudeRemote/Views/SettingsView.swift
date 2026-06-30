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
                            .font(.brandBody(16))
                    }
                }
                Section("终端") {
                    Slider(value: $fontSize, in: 9...20) {
                        Text("字体大小")
                            .font(.brandBody(16))
                    }
                    Text(String(format: "%.0f pt", fontSize))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.brandOrange)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.brandDark)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundColor(.brandOrange)
                }
            }
        }
    }
}
