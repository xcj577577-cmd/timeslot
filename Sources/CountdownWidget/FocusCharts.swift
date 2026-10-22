import Charts
import SwiftUI

/// 科目堆叠日柱。首页用矮图，统计页用高图；Y 轴小时，虚线为日均或周目标/7。
struct StackedFocusChart: View {
    let points: [PomodoroDailyFocusPoint]
    let days: [Date]
    let taskColor: (String) -> Color
    var height: CGFloat = 88
    var dailyTargetHours: Double? = nil
    var averageHours: Double? = nil
    var selectedDate: Date? = nil
    var onSelectDate: ((Date?) -> Void)? = nil

    private var order: [String] {
        FocusStats.taskOrder(in: points)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("日期", point.day, unit: .day),
                    y: .value("小时", point.duration / 3600),
                    width: .ratio(0.58)
                )
                .foregroundStyle(by: .value("任务", point.taskTitle))
                .cornerRadius(3)
                .accessibilityLabel(
                    "\(beijingDateString(point.day, dateStyle: .abbreviated, timeStyle: .omitted)) \(point.taskTitle)"
                )
                .accessibilityValue(FocusStats.durationText(point.duration))
            }
            if let dailyTargetHours, dailyTargetHours > 0 {
                RuleMark(y: .value("日均目标", dailyTargetHours))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            } else if let averageHours, averageHours > 0 {
                RuleMark(y: .value("日均", averageHours))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let selectedDate {
                RuleMark(x: .value("选中日期", selectedDate, unit: .day))
                    .foregroundStyle(Color.primary.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(
            domain: order,
            range: order.map { taskColor($0) }
        )
        .chartLegend(.hidden)
        .chartXScale(domain: (days.first ?? Date())...(days.last ?? Date()))
        .chartXAxis {
            if days.count <= 8 {
                AxisMarks(values: days) { value in
                    AxisValueLabel {
                        if let day = value.as(Date.self) {
                            Text(weekdayLetter(day))
                        }
                    }
                    .font(AppType.caption(11, weight: .medium))
                }
            } else {
                AxisMarks(values: .automatic(desiredCount: 7)) { value in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(AppType.caption(11, weight: .medium))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Surface.gridLine)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(String(format: "%gh", hours))
                            .font(AppType.caption(11))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            if let onSelectDate {
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { location in
                        if let plot = proxy.plotFrame, geometry[plot].contains(location) {
                            onSelectDate(proxy.value(atX: location.x - geometry[plot].minX))
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .environment(\.calendar, beijingCalendar)
        .environment(\.timeZone, beijingTimeZone)
        .environment(\.locale, beijingLocale)
    }

    private func weekdayLetter(_ date: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return names[beijingCalendar.component(.weekday, from: date) - 1]
    }
}
