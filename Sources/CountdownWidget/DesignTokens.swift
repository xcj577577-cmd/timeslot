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
        case .teal: return "极光青"
        case .coral: return "日落橙"
        case .indigo: return "经典蓝"
        case .violet: return "优雅紫"
        case .graphite: return "深空灰"
        }
    }

    /// 浅色外观下的主色 (Apple HIG Precision)。
    var lightHex: String {
        switch self {
        case .teal: return "#00A396"
        case .coral: return "#FF9500"
        case .indigo: return "#007AFF"
        case .violet: return "#AF52DE"
        case .graphite: return "#8E8E93"
        }
    }

    /// 深色外观下的主色：通透清亮，符合 Apple Dark Mode 标准。
    var darkHex: String {
        switch self {
        case .teal: return "#30D1C7"
        case .coral: return "#FF9F0A"
        case .indigo: return "#0A84FF"
        case .violet: return "#BF5AF2"
        case .graphite: return "#98989D"
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
                    .font(AppType.ui(Typo.footnote, isSelected ? .semibold : .medium))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 32)
                    .padding(.horizontal, Space.s)
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [tint, tint.opacity(0.88)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .matchedGeometryEffect(id: "selection", in: selectionAnimation)
                                    .shadow(color: tint.opacity(0.32), radius: 5, y: 1.5)
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
        .padding(3)
        .background(Surface.field, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            color.opacity(0.12),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.24), lineWidth: 1)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: progress)
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: progress)
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

    private let colors: [Color] = [
        Color(hex: "#D86F52"),
        Color(hex: "#2C8C7C"),
        Color(hex: "#B07A3A"),
        Color(hex: "#5A78B8"),
        Color(hex: "#7B5EA7"),
        Color(hex: "#E0B354")
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
                    withAnimation(.easeOut(duration: 2.2)) {
                        animProgress = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        pieces = []
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
