import AppKit
import SwiftUI

let beijingTimeZone = TimeZone(identifier: "Asia/Shanghai")
    ?? TimeZone(secondsFromGMT: 8 * 60 * 60)
    ?? .current
let beijingLocale = Locale(identifier: "zh_CN")

var beijingCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = beijingTimeZone
    calendar.locale = beijingLocale
    return calendar
}

func beijingDateString(
    _ date: Date,
    dateStyle: Date.FormatStyle.DateStyle,
    timeStyle: Date.FormatStyle.TimeStyle
) -> String {
    let format = Date.FormatStyle(
        date: dateStyle,
        time: timeStyle,
        locale: beijingLocale,
        calendar: beijingCalendar,
        timeZone: beijingTimeZone
    )
    return date.formatted(format)
}

@MainActor let countdownDefaults =
    UserDefaults(suiteName: "4FKFDX48HX.com.xianz.countdownwidget.shared") ?? .standard

// MARK: - 设计令牌
//
// 字体、间距和表面层级集中在这里，避免不同页面各自“调一点”后失去一致性。
// UI 字体使用 macOS 系统字形（中文自动落到苹方），只有计时数字使用圆体，
// 让阅读和品牌识别各自承担清晰的职责。

/// 品牌色只在这里定义。Logo、强调色与状态色都从这组颜色派生，
/// 避免主应用、表单和小组件出现“差不多的青绿”。
enum BrandPalette {
    static let ink = Color(hex: "#1A1A1F")
    static let deepTeal = Color(hex: "#29423E")
    static let teal = Color(hex: "#55A99C")
    static let mint = Color(hex: "#A0D0C5")
    static let gold = Color(hex: "#C7A35A")
    static let goldHighlight = Color(hex: "#E7D6A2")
    static let coral = Color(hex: "#C07862")
    static let indigo = Color(hex: "#8B83A6")
}

/// 数据洞察的信号调色板：低饱和、可区分，避免统计页面变成彩色装饰墙。
/// 顺序固定，任务/时段的分类色按序取用，保证图例与图表一致。
enum DataGradient {
    static func palette(_ index: Int) -> [Color] {
        let palettes: [[Color]] = [
            [Color(hex: "#55A99C"), Color(hex: "#A0D0C5")],       // 青绿
            [Color(hex: "#C7A35A"), Color(hex: "#E7D6A2")],       // 金
            [Color(hex: "#C07862"), Color(hex: "#D9A18E")],       // 珊瑚
            [Color(hex: "#879C87"), Color(hex: "#B8C5B4")],       // 苔绿
            [Color(hex: "#8B83A6"), Color(hex: "#B8B1C8")],       // 紫灰
            [Color(hex: "#B47D89"), Color(hex: "#D2AAB3")],       // 玫瑰灰
            [Color(hex: "#A8894A"), Color(hex: "#D0B978")],       // 深金
            [Color(hex: "#B98960"), Color(hex: "#D1B18E")]        // 琥珀灰
        ]
        return palettes[index % palettes.count]
    }

    static func base(_ index: Int) -> Color { palette(index)[0] }

    /// 卡片顶部的一抹氛围色带：低透明度渐变，不给读数添噪。
    static func wash(_ index: Int, isDark: Bool) -> Color {
        base(index).opacity(isDark ? 0.16 : 0.10)
    }
}

/// 用户数据中已经保存的识别色保持原样；渲染时统一映射到当前的低饱和信号系统。
/// 这样历史记录、任务、倒计时和图表能保持同一颜色含义，而不用迁移或改写任何本地数据。
enum DataSignal {
    private static let presentationHexByStoredHex: [String: String] = [
        "#2C8C7C": "#55A99C",
        "#D86F52": "#C07862",
        "#E2B84A": "#C7A35A",
        "#B07A3A": "#A8894A",
        "#7B5EA7": "#8B83A6",
        "#4C9A5A": "#879C87",
        "#C2557A": "#B47D89",
        "#3E8FA8": "#66969D",
        "#5A78B8": "#8B83A6"
    ]

    static func presentationHex(for storedHex: String) -> String {
        presentationHexByStoredHex[storedHex.uppercased()] ?? storedHex
    }

    static func color(hex storedHex: String, isDark: Bool = false) -> Color {
        let rgba = ColorHex.rgba(from: presentationHex(for: storedHex))
            ?? ColorHex.rgba(from: ColorHex.fallback)
            ?? (red: 0.17, green: 0.55, blue: 0.49, alpha: 1)
        guard isDark else {
            return Color(
                .sRGB,
                red: Double(rgba.red),
                green: Double(rgba.green),
                blue: Double(rgba.blue),
                opacity: Double(rgba.alpha)
            )
        }
        let lift: CGFloat = 0.12
        return Color(
            .sRGB,
            red: Double(rgba.red + (1 - rgba.red) * lift),
            green: Double(rgba.green + (1 - rgba.green) * lift),
            blue: Double(rgba.blue + (1 - rgba.blue) * lift),
            opacity: Double(rgba.alpha)
        )
    }
}

/// 品牌母题的几何原语：右倾的金色平行四边形。
/// 只出现在进度条末端和圆环尖端，不改读数排版，也不另起装饰层。
struct TimeSlotWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.32))
        path.closeSubpath()
        return path
    }
}
/// 字号阶梯。正文保持清晰的 12 / 13.5 / 14.5 / 17 层级，再单独处理标题和计时读数。
enum Typo {
    static let caption: CGFloat = 12      // 单位、角标、图例
    static let footnote: CGFloat = 13.5   // 说明文字、列表副标题
    static let body: CGFloat = 14.5       // 正文、按钮、行标题
    static let headline: CGFloat = 17     // 小节标题、强调数值
    static let sheetTitle: CGFloat = 22   // 弹窗标题
    static let brand: CGFloat = 22        // 侧栏品牌名
    static let pageTitle: CGFloat = 30    // 页面主标题
    static let icon: CGFloat = 28         // 空状态图标
    static let timerSmall: CGFloat = 36   // 侧栏计时读数
    static let timerLarge: CGFloat = 56   // 主计时读数
}

/// 字距统一取值：中文标题不额外拉开，短标签和计时数字只保留极少呼吸感。
enum Tracking {
    static let pageTitle: CGFloat = 0.0   // 页面主标题、品牌名
    static let heading: CGFloat = 0.0     // 卡片小节标题
    static let label: CGFloat = 0.2       // caption 小标签
    static let timer: CGFloat = 0.2       // 计时读数
    static let caption: CGFloat = 0.0     // 说明性副文本
}

/// 间距节奏，4 的倍数。
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// 表面层级。关键点：嵌套卡片必须比父卡片**更重**才分得开，
/// 原来父 0.035 里套 0.025，同色系里更浅的块几乎看不出边界。
enum Surface {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let nested = Color.primary.opacity(0.075)
    static let field = Color.primary.opacity(0.065)
    static let track = Color.primary.opacity(0.11)
    static let gridLine = Color.primary.opacity(0.07)  // 图表网格线
    static let border = Color.primary.opacity(0.10)
}

/// 侧栏衬底。工作台左轨直接铺在画布上，不再单独铺一层色板。
struct SidebarSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Surface.canvas
            .overlay {
                if colorScheme == .dark {
                    Color.white.opacity(0.025)
                } else {
                    Color.black.opacity(0.032)
                }
            }
    }
}

/// 主画布：纯色底 + 一条静态顶光。未来感来自留白与层次，不靠装饰。
struct FrostedCanvas: View {
    var theme: ColorPreset = .graphite
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(hex: theme.canvasDark[1]), Color(hex: theme.canvasDark[0])]
                : [Color(hex: theme.canvasLight[1]), Color(hex: theme.canvasLight[0])],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

enum Radius {
    static let small: CGFloat = 7
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
    static let board: CGFloat = 18
    static let pill: CGFloat = 999
}

/// 统一字体入口。Logo 仍用衬线；其余界面用圆体，中文自动落到苹方圆体。
///
/// - ui：界面正文。
/// - title：小节标题。
/// - pageTitle：页面主标题，字重更轻。
/// - timer：计时数字，等宽圆体。
/// - caption：辅助小字。
enum AppType {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func pageTitle(_ size: CGFloat = Typo.pageTitle) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    static func timer(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func caption(_ size: CGFloat = Typo.caption, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// 内嵌卡片表面：单层纯色 + 细边框，与看板靠明度差分层。
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Radius.medium
    var borderOpacity: Double = 0.10
    var shadowRadius: CGFloat = 12
    var shadowY: CGFloat = 3
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.78))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color.primary.opacity(
                            colorScheme == .dark
                                ? min(0.16, borderOpacity + 0.02)
                                : max(0.05, borderOpacity * 0.82)
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.045),
                radius: min(max(shadowRadius, 0), 14),
                y: min(max(shadowY, 0), 6)
            )
    }
}

struct NestedSurface: ViewModifier {
    var cornerRadius: CGFloat = Radius.small
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.04),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

extension View {
    func cardSurface(
        cornerRadius: CGFloat = Radius.medium,
        borderOpacity: Double = 0.07,
        shadowRadius: CGFloat = 10,
        shadowY: CGFloat = 3
    ) -> some View {
        modifier(CardSurface(
            cornerRadius: cornerRadius,
            borderOpacity: borderOpacity,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        ))
    }

    func nestedSurface(cornerRadius: CGFloat = Radius.small) -> some View {
        modifier(NestedSurface(cornerRadius: cornerRadius))
    }

    func glassBoard(cornerRadius: CGFloat = Radius.board, wash: Color = .clear) -> some View {
        modifier(GlassBoard(cornerRadius: cornerRadius, wash: wash))
    }

    func inkPill() -> some View {
        modifier(InkPillChrome())
    }
}

/// 工作台幽灵按钮底：浅纸面胶囊，不跟强调色。
struct InkPillChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
                    .overlay(Capsule().stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1))
            )
    }
}

/// 工作台看板：浮在暖色画布上的磨砂圆角板，左右两块彼此分开。
struct GlassBoard: ViewModifier {
    var cornerRadius: CGFloat = Radius.board
    var wash: Color = .clear
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.66))
                    .overlay {
                        if wash != .clear {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(wash.opacity(colorScheme == .dark ? 0.07 : 0.08))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.05), radius: 14, y: 5)
    }
}

/// 通用按压反馈：按下时轻微缩小并降低不透明度，配合 0.1s 短动画，
/// 让自定义（.plain）按钮也有 macOS 原生般的点击反馈，不再“点下去没反应”。
/// 不重写背景，可与选中态/描边等既有视觉叠加。
struct TimeSlotPressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
// MARK: - 外观模式

/// 应用外观：跟随系统、强制浅色或强制深色。
/// 通过 NSApp.appearance 全局生效（含弹窗与侧栏），SwiftUI 会随 appearance 自动重渲染。
enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// nil 表示跟随系统。
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - 颜色预设

/// 品牌强调色预设。每个预设提供浅色/深色两档主色，
/// 深色档比浅色档亮一档，保证两种外观下都清晰可读。
enum ColorPreset: String, Codable, CaseIterable, Identifiable {
    case graphite

    var id: String { rawValue }

    var title: String { "石墨灰" }

    var subtitle: String { "中性纸面，石墨点缀" }

    var lightHex: String { "#5C5C66" }

    var darkHex: String { "#A8A8B0" }

    var canvasLight: [String] { ["#F4F4F6", "#F7F7F8", "#EEEEF0"] }

    var canvasDark: [String] { ["#0D0D10", "#121215", "#0F0F12"] }

    func wash(isDark: Bool) -> Color {
        Color(hex: isDark ? canvasDark[1] : canvasLight[0])
    }

    var breakHex: String { "#6B6B74" }

    var longBreakHex: String { "#4F4F58" }

    var color: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? darkHex : lightHex)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        let rgba = ColorHex.rgba(from: hex) ?? (0.17, 0.55, 0.49, 1)
        self.init(
            srgbRed: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            alpha: rgba.alpha
        )
    }
}

extension Color {
    init(hex: String) {
        let rgba = ColorHex.rgba(from: hex) ?? (0.17, 0.55, 0.49, 1)
        self.init(
            .sRGB,
            red: Double(rgba.red),
            green: Double(rgba.green),
            blue: Double(rgba.blue),
            opacity: Double(rgba.alpha)
        )
    }
}

struct SegmentOption<Value: Hashable>: Identifiable {
    let id: String
    let title: String
    let systemImage: String?
    let value: Value

    init(id: String, title: String, systemImage: String? = nil, value: Value) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.value = value
    }
}

/// 分段控件：选中态用墨色纸面，不再铺一层强调色。
struct TimeSlotSegmentedControl<Value: Hashable>: View {
    let options: [SegmentOption<Value>]
    @Binding var selection: Value
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = selection == option.value
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.04)) {
                        selection = option.value
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        if let systemImage = option.systemImage {
                            Image(systemName: systemImage)
                                .imageScale(.small)
                                .symbolRenderingMode(.hierarchical)
                        }
                        Text(option.title)
                    }
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 30)
                    .padding(.horizontal, 8)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .background(
                        Group {
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08))
                                    .overlay(
                                        Capsule()
                                            .stroke(tint.opacity(colorScheme == .dark ? 0.34 : 0.22), lineWidth: 1)
                                    )
                                    .matchedGeometryEffect(id: "selection", in: selectionAnimation)
                            }
                        }
                    )
                }
                .buttonStyle(TimeSlotPressableStyle())
                .contentShape(Capsule())
                .accessibilityLabel(option.title)
                .accessibilityIdentifier("timeslot.segment.\(option.id)")
                .accessibilityValue(isSelected ? "已选中" : "未选中")
            }
        }
        .padding(3)
        .background(
            Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.045),
            in: Capsule()
        )
    }
}

/// 精致状态胶囊徽章：用于呈现 进行中、已暂停、已结束、紧急截止 等状态
struct StatusPillBadge: View {
    let title: String
    var icon: String? = nil
    let color: Color
    var isPulsing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            } else if isPulsing {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.6), radius: 3)
            }
            Text(title)
                .font(AppType.caption(Typo.caption, weight: .semibold))
        }
        .foregroundStyle(color.opacity(0.92))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            color.opacity(0.10),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}

/// 模块化时间单元卡片：展示大号时间数值 + 单位标签（天、时、分、秒）
struct TimeDigitBlock: View {
    let value: String
    let label: String
    let color: Color
    var minWidth: CGFloat = 64

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppType.timer(Typo.timerSmall + 2))
                .tracking(Tracking.timer)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(AppType.caption(11, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: minWidth)
        .padding(.vertical, Space.s)
        .padding(.horizontal, Space.s)
        .background(Surface.nested, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

/// 精致进度条：浅色轨道 + 品牌渐变填充 + 金色楔形标记。
struct TimeSlotProgressBar: View {
    let progress: CGFloat
    let color: Color
    var height: CGFloat = 8
    var showsKnob: Bool = true
    var showsMilestones: Bool = false
    /// 高频时间线使用直接更新，避免每秒启动一段 350ms 的动画并持续触发布局。
    var animatesProgress: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, progress))
            let width = max(0, proxy.size.width) * clamped
            let wedgeWidth = height * 0.72
            let wedgeHeight = height * 1.55

            ZStack(alignment: .leading) {
                // 背景轨道
                Capsule()
                    .fill(Surface.track)

                // 里程碑刻度线 (25%, 50%, 75%)
                if showsMilestones {
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: height * 0.7)
                        Spacer()
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: height * 0.7)
                        Spacer()
                        Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: height * 0.7)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                }

                // 进度填充
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.82)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
                    .shadow(color: color.opacity(0.28), radius: 3, x: 0, y: 1)
            }
            .overlay(alignment: .leading) {
                if showsKnob, clamped > 0.02 {
                    TimeSlotWedge()
                        .fill(
                            LinearGradient(
                                colors: [BrandPalette.goldHighlight, BrandPalette.gold],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: wedgeWidth, height: wedgeHeight)
                        .shadow(color: BrandPalette.gold.opacity(0.48), radius: 3.5, x: 0, y: 1)
                        .offset(
                            x: min(
                                max(width - wedgeWidth * 0.55, 0),
                                max(0, proxy.size.width - wedgeWidth)
                            )
                        )
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: showsKnob ? height + 6 : height)
        .animation(animatesProgress && !reduceMotion ? .easeOut(duration: 0.35) : nil, value: progress)
    }
}

/// 精致圆环：浅色轨道 + 渐变圆弧 + 呼吸光晕 + 品牌金色时隙楔形。
struct TimeSlotRing: View {
    let progress: CGFloat
    let color: Color
    var lineWidth: CGFloat = 12
    var showsGlow: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(1, max(0, progress))
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = max(0, (side - lineWidth) / 2)
            let theta = Angle.degrees(-90 + Double(clamped) * 360)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let tip = CGPoint(
                x: center.x + CGFloat(cos(theta.radians)) * radius,
                y: center.y + CGFloat(sin(theta.radians)) * radius
            )

            ZStack {
                // 外层环境柔光
                if showsGlow && clamped > 0.01 {
                    Circle()
                        .stroke(color.opacity(0.12), lineWidth: lineWidth * 1.6)
                        .blur(radius: 6)
                }

                // 底层轨道
                Circle()
                    .stroke(Surface.track, lineWidth: lineWidth)

                // 进度圆弧
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        LinearGradient(
                            colors: [color, color.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: showsGlow ? color.opacity(0.35) : .clear, radius: 8)

                // 尖端金色时隙楔形
                if clamped > 0.02 {
                    TimeSlotWedge()
                        .fill(
                            LinearGradient(
                                colors: [BrandPalette.goldHighlight, BrandPalette.gold],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: lineWidth * 0.62, height: lineWidth * 1.45)
                        .rotationEffect(.degrees(Double(clamped) * 360))
                        .position(tip)
                        .shadow(color: BrandPalette.gold.opacity(showsGlow ? 0.52 : 0.25), radius: 3.5)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: progress)
    }
}

/// 辉光渐变计时环：Moonshot 式宇宙光感，多层柔光 + 角向渐变弧 + 头部辉光点 + 金色楔形尖端。
struct TimeSlotGlowRing: View {
    let progress: CGFloat
    let color: Color
    var lineWidth: CGFloat = 12
    var showsGlow: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(1, max(0, progress))
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = max(0, (side - lineWidth) / 2)
            let theta = Angle.degrees(-90 + Double(clamped) * 360)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let tip = CGPoint(
                x: center.x + CGFloat(cos(theta.radians)) * radius,
                y: center.y + CGFloat(sin(theta.radians)) * radius
            )

            ZStack {
                // 多层柔光：从环向外晕开
                if showsGlow && clamped > 0.01 {
                    Circle()
                        .stroke(color.opacity(0.05), lineWidth: lineWidth + 26)
                        .blur(radius: 18)
                    Circle()
                        .stroke(color.opacity(0.10), lineWidth: lineWidth + 12)
                        .blur(radius: 9)
                }

                // 底层轨道
                Circle()
                    .stroke(color.opacity(0.10), lineWidth: lineWidth)

                // 角向渐变进度弧：头部亮、尾段淡，像光在环上游走
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(
                            colors: [
                                color.opacity(0.18),
                                color.opacity(0.75),
                                color.opacity(0.95)
                            ],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: showsGlow ? color.opacity(0.45) : .clear, radius: 9)

                // 头部辉光点：紧贴进度头的亮芯
                if clamped > 0.02 {
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth * 0.85, height: lineWidth * 0.85)
                        .position(tip)
                        .shadow(color: color.opacity(0.9), radius: 7)

                    // 金色时隙楔形
                    TimeSlotWedge()
                        .fill(
                            LinearGradient(
                                colors: [BrandPalette.goldHighlight, BrandPalette.gold],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: lineWidth * 0.62, height: lineWidth * 1.45)
                        .rotationEffect(.degrees(Double(clamped) * 360))
                        .position(tip)
                        .shadow(color: BrandPalette.gold.opacity(showsGlow ? 0.52 : 0.25), radius: 3.5)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.08), value: progress)
    }
}

// MARK: - 星点背景与光带仪表（Moonshot 式宇宙质感）

/// 静谧星点：极淡的点阵铺在卡片/画布上，缓慢闪烁，不抢内容，只提供宇宙氛围。
struct StarField: View {
    var density: Int = 64
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 10 : 0.3)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for index in 0..<density {
                    let x = CGFloat((index * 137) % 1000) / 1000 * size.width
                    let y = CGFloat((index * 331) % 1000) / 1000 * size.height
                    let radius = CGFloat(1.0 + CGFloat((index * 7) % 10) * 0.16)
                    // 每颗星独立相位闪烁，幅度更大
                    let phase = Double((index * 47) % 100) / 100 * .pi * 2
                    let twinkle = 0.55 + 0.45 * sin(t * 1.1 + phase)
                    let baseAlpha = 0.22 + CGFloat((index * 13) % 8) * 0.06
                    let alpha = baseAlpha * CGFloat(twinkle)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(Color.primary.opacity(alpha))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 光带仪表计时器：超大辉光数字 + 水平渐变光带进度 + 头部光点与金色楔形。
/// 彻底取代圆环，数字是绝对主角，进度像一束光沿轨道推进。
struct TimeSlotGlowMeter: View {
    let progress: CGFloat
    let color: Color
    let phaseTitle: String
    let phaseIcon: String
    let timeText: String
    let isRunning: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var glowBarWidth: CGFloat = 300

    var body: some View {
        let clamped = min(1, max(0, progress))
        VStack(spacing: 22) {
            // 阶段胶囊
            HStack(spacing: 8) {
                Image(systemName: phaseIcon)
                Text(phaseTitle)
            }
            .font(AppType.ui(14, .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
            .symbolEffect(.pulse, isActive: isRunning && !reduceMotion)

            // 超大辉光数字
            Text(timeText)
                .font(.system(size: 96, weight: .regular, design: .monospaced))
                .tracking(-2)
                .monospacedDigit()
                .foregroundStyle(color)
                .shadow(color: color.opacity(isRunning ? 0.42 : 0.22), radius: 16)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: 360)

            // 水平渐变光带：头部亮、尾段淡，带光点推进
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.10))
                    .frame(height: 10)

                // 25% 间隔的仪器刻度点
                HStack {
                    ForEach(0..<5) { index in
                        Circle()
                            .fill(Color.primary.opacity(index == 0 ? 0 : 0.22))
                            .frame(width: 3, height: 3)
                        if index < 4 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, 2)
                .allowsHitTesting(false)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.32), color, color.opacity(0.82)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(10, glowBarWidth * clamped), height: 10)
                    .shadow(color: color.opacity(0.36), radius: 5)

                if clamped > 0.02 {
                    Circle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 13, height: 13)
                        .offset(x: max(0, glowBarWidth * clamped) - 6.5)
                        .shadow(color: Color.white.opacity(0.7), radius: 5)

                    TimeSlotWedge()
                        .fill(
                            LinearGradient(
                                colors: [BrandPalette.goldHighlight, BrandPalette.gold],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 8, height: 16)
                        .offset(x: max(0, glowBarWidth * clamped) - 2)
                        .shadow(color: BrandPalette.gold.opacity(0.6), radius: 4)
                }
            }
            .frame(width: glowBarWidth, height: 18)
            .animation(reduceMotion ? nil : .linear(duration: 0.12), value: progress)

            // 状态
            HStack(spacing: 7) {
                Circle()
                    .fill(isRunning ? color : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .shadow(color: isRunning ? color.opacity(0.6) : .clear, radius: 4)
                Text(isRunning ? "RUNNING" : "STANDBY")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 庆祝彩带粒子动效 (Confetti Particle Celebration)

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGSize
    let initialX: CGFloat
    let initialY: CGFloat
    let velocityX: CGFloat
    let velocityY: CGFloat
    let spin: Double
    let spinSpeed: Double
}

struct ConfettiEffectView: View {
    let isActive: Bool
    @State private var pieces: [ConfettiPiece] = []
    @State private var animProgress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors: [Color] = [
        DataGradient.base(0),
        DataGradient.base(1),
        DataGradient.base(2),
        DataGradient.base(3),
        DataGradient.base(4),
        DataGradient.base(5)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if isActive {
                    ForEach(pieces) { piece in
                        let progress = Double(animProgress)
                        let currentX = piece.initialX + piece.velocityX * progress * proxy.size.width
                        let currentY = piece.initialY + (piece.velocityY * progress + 0.5 * 9.8 * progress * progress * 0.45) * proxy.size.height
                        let opacity = max(0, 1.0 - progress * 1.05)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(piece.color)
                            .frame(width: piece.size.width, height: piece.size.height)
                            .rotationEffect(.degrees(piece.spin + piece.spinSpeed * progress * 360))
                            .opacity(opacity)
                            .position(x: currentX, y: currentY)
                    }
                }
            }
            .onAppear {
                if isActive {
                    generatePieces(in: proxy.size)
                }
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    generatePieces(in: proxy.size)
                    animProgress = 0
                    if reduceMotion {
                        pieces = []
                    } else {
                        withAnimation(.easeOut(duration: 2.2)) {
                            animProgress = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            pieces = []
                        }
                    }
                } else {
                    pieces = []
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func generatePieces(in size: CGSize) {
        var result: [ConfettiPiece] = []
        for _ in 0..<36 {
            let color = colors.randomElement() ?? .orange
            let w = CGFloat.random(in: 6...11)
            let h = CGFloat.random(in: 8...16)
            let initX = size.width * CGFloat.random(in: 0.3...0.7)
            let initY = size.height * CGFloat.random(in: 0.3...0.6)
            let vx = CGFloat.random(in: -0.6...0.6)
            let vy = CGFloat.random(in: -0.8...(-0.2))
            let spin = Double.random(in: 0...360)
            let speed = Double.random(in: 1.5...4.0) * (Bool.random() ? 1 : -1)
            result.append(ConfettiPiece(
                color: color,
                size: CGSize(width: w, height: h),
                initialX: initX,
                initialY: initY,
                velocityX: vx,
                velocityY: vy,
                spin: spin,
                spinSpeed: speed
            ))
        }
        pieces = result
    }
}

// MARK: - 提示声音效管理器

public enum SoundEffectPreset: String, CaseIterable, Identifiable {
    case glass = "清脆水晶"
    case ping = "经典提示"
    case tink = "轻快敲击"
    case submarine = "深潜声呐"
    case hero = "凯旋号角"
    case purr = "柔和猫鸣"

    public var id: String { rawValue }

    public var systemSoundName: String {
        switch self {
        case .glass: return "Glass"
        case .ping: return "Ping"
        case .tink: return "Tink"
        case .submarine: return "Submarine"
        case .hero: return "Hero"
        case .purr: return "Purr"
        }
    }

    public func play() {
        if let sound = NSSound(named: systemSoundName) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
