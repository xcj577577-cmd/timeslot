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
    static let ink = Color(hex: "#0A1926")
    static let deepTeal = Color(hex: "#103D3B")
    static let teal = Color(hex: "#35B79F")
    static let mint = Color(hex: "#8CE4D0")
    static let gold = Color(hex: "#E8C27A")
    static let goldHighlight = Color(hex: "#F3D69B")
    static let coral = Color(hex: "#D86F52")
    static let indigo = Color(hex: "#5A78B8")
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

/// 侧栏和窗口画布只做轻微明度分层。
/// `underPageBackgroundColor` 在浅色 Aqua 下是中灰色，适合页面背后的衬底，
/// 不适合作为常驻侧栏；强制从深色切回浅色时会显得像外观没有刷新。
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

enum Radius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let pill: CGFloat = 999
}

/// 统一字体入口。
///
/// - ui：界面正文。使用 macOS 系统字形，保证中文、拉丁字母和控件文字的阅读稳定性。
/// - title：标题。使用系统半粗，不用圆体抢正文的注意力。
/// - pageTitle：页面主标题。中等字重，配合更大的字号建立清晰的页面入口。
/// - timer：计时数字。圆体 + 等宽数字，走秒时宽度稳定且有品牌识别度。
/// - caption：辅助小字。
enum AppType {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    /// 页面主标题：系统半粗字重，中文自动落到苹方，避免大标题显得发胀。
    static func pageTitle(_ size: CGFloat = Typo.pageTitle) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func timer(_ size: CGFloat) -> Font {
        // medium 字重：56pt 大数字用 semibold 会发胖，medium 更接近系统计时器质感的轻盈读数。
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func caption(_ size: CGFloat = Typo.caption, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// 统一卡片表面：浅色底 + 细描边 + 极轻阴影。
/// 之前每张卡各写各的 overlay/stroke，深浅和圆角都不一致，视觉上零碎。
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Radius.medium
    var borderOpacity: Double = 0.10
    var shadowRadius: CGFloat = 12
    var shadowY: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Surface.card)
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(0.035), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(borderOpacity), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.055), radius: shadowRadius, x: 0, y: shadowY)
    }
}

struct NestedSurface: ViewModifier {
    var cornerRadius: CGFloat = Radius.small

    func body(content: Content) -> some View {
        content
            .background(Surface.nested)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.055), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
    case teal
    case coral
    case indigo
    case violet
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teal: return "青绿"
        case .coral: return "珊瑚"
        case .indigo: return "靛蓝"
        case .violet: return "紫罗兰"
        case .graphite: return "石墨"
        }
    }

    /// 浅色外观下的主色。
    var lightHex: String {
        switch self {
        case .teal: return "#2C8C7C"
        case .coral: return "#C96A4E"
        case .indigo: return "#5A78B8"
        case .violet: return "#7B5EA7"
        case .graphite: return "#5B6573"
        }
    }

    /// 深色外观下的主色：比浅色档亮一档，避免深色底上发闷。
    var darkHex: String {
        switch self {
        case .teal: return "#45A68F"
        case .coral: return "#E08A6E"
        case .indigo: return "#8098D4"
        case .violet: return "#9D81C8"
        case .graphite: return "#8A94A1"
        }
    }

    /// 跟随系统深浅外观的动态主色。
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

/// 品牌化分段控件。macOS 原生 segmented Picker 在失焦时会退回系统蓝/灰，
/// 这里把选中态固定为时隙的青绿色，确保窗口状态变化时视觉仍然稳定。
struct TimeSlotSegmentedControl<Value: Hashable>: View {
    let options: [SegmentOption<Value>]
    @Binding var selection: Value
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .font(AppType.ui(Typo.footnote, .medium))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 32)
                    .padding(.horizontal, Space.s)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                    .fill(tint)
                                    .matchedGeometryEffect(id: "selection", in: selectionAnimation)
                                    .shadow(color: tint.opacity(0.22), radius: 4, y: 1)
                            }
                        }
                    )
                }
                .buttonStyle(TimeSlotPressableStyle())
                .contentShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                .accessibilityLabel(option.title)
                .accessibilityIdentifier("timeslot.segment.\(option.id)")
                .accessibilityValue(isSelected ? "已选中" : "未选中")
            }
        }
        .padding(2)
        .background(Surface.field, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// 精致进度条：浅色轨道 + 品牌渐变填充。
/// 末端用金色楔形代替圆点——进度走到哪里，「时隙」就停在哪里。
struct TimeSlotProgressBar: View {
    let progress: CGFloat
    let color: Color
    var height: CGFloat = 8
    var showsKnob: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, progress))
            let width = max(0, proxy.size.width) * clamped
            let wedgeWidth = height * 0.72
            let wedgeHeight = height * 1.55

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Surface.track)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.76)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
                    .shadow(color: color.opacity(0.26), radius: 3, x: 0, y: 1)
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
                        .shadow(color: BrandPalette.gold.opacity(0.42), radius: 3, x: 0, y: 1)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: progress)
    }
}

/// 精致圆环：浅色轨道 + 渐变圆弧。
/// 进度尖端落一枚金色楔形，让「现在」在圆环上也是那道时隙。
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
                Circle()
                    .stroke(Surface.track, lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        LinearGradient(
                            colors: [color, color.opacity(0.80)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: showsGlow ? color.opacity(0.30) : .clear, radius: 7)

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
                        .shadow(color: BrandPalette.gold.opacity(showsGlow ? 0.45 : 0.2), radius: 3)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: progress)
    }
}
