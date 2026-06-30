import SwiftUI

/// Anthropic 品牌色（来自 brand-guidelines skill）
extension Color {
    static let brandDark = Color(red: 0x14/255, green: 0x14/255, blue: 0x13/255)       // #141413 主文字/深背景
    static let brandLight = Color(red: 0xfa/255, green: 0xf9/255, blue: 0xf5/255)     // #faf9f5 浅背景/深色上的文字
    static let brandMidGray = Color(red: 0xb0/255, green: 0xae/255, blue: 0xa5/255)   // #b0aea5 次要元素
    static let brandLightGray = Color(red: 0xe8/255, green: 0xe6/255, blue: 0xdc/255) // #e8e6dc 微妙背景
    static let brandOrange = Color(red: 0xd9/255, green: 0x77/255, blue: 0x57/255)    // #d97757 主强调色
    static let brandBlue = Color(red: 0x6a/255, green: 0x9b/255, blue: 0xcc/255)      // #6a9bcc 次强调色
    static let brandGreen = Color(red: 0x78/255, green: 0x8c/255, blue: 0x5d/255)     // #788c5d 三强调色
}

/// 品牌字体（Poppins 标题 / Lora 正文）
/// 注意：iOS 不预装 Poppins/Lora，需用户通过 iFont 等工具安装配置文件。
/// 未安装时 SwiftUI 自动 fallback 到系统字体，不影响功能。
extension Font {
    static func brandTitle(_ size: CGFloat) -> Font { .custom("Poppins", size: size) }
    static func brandBody(_ size: CGFloat) -> Font { .custom("Lora", size: size) }
}
