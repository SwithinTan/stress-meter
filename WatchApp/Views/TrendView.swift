import SwiftUI
import Charts
import StressCore

struct TrendView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                if model.isDemo { DemoBadge() }
                Text("近 7 天").font(.title3.weight(.semibold))
                Text("只显示实际可估算的样本")
                    .font(.caption2).foregroundStyle(.secondary)
                if model.history.isEmpty {
                    ContentUnavailableView("暂无趋势", systemImage: "chart.dots.scatter",
                                           description: Text("积累足够的个人基线后，这里会显示观测点。"))
                } else {
                    Chart(model.history, id: \.id) { point in
                        PointMark(x: .value("时间", point.date), y: .value("水平", point.level.rank))
                            .foregroundStyle(point.level.tint)
                            .symbolSize(15)
                            .accessibilityLabel("\(point.date.formatted(date: .abbreviated, time: .shortened))，\(point.level.title)")
                    }
                    .chartYScale(domain: -0.3...2.3)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 1, 2]) { value in
                            AxisGridLine().foregroundStyle(.white.opacity(0.08))
                            AxisValueLabel {
                                if let rank = value.as(Int.self) {
                                    Text(["低", "常", "高"][min(2, max(0, rank))]).font(.system(size: 9))
                                }
                            }
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                    .frame(height: 115)
                    ForEach(Array(model.history.suffix(12).reversed()), id: \.id) { point in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(point.date, format: .dateTime.month().day())
                                Text(point.date, style: .time).foregroundStyle(.secondary)
                            }.font(.caption2)
                            Spacer()
                            Text(point.level.title).font(.footnote.weight(.medium)).foregroundStyle(point.level.tint)
                        }
                        .padding(.vertical, 3)
                    }
                }
                Text("空白表示没有可用估算，不能解释为压力平稳。不同时间的观测点不会连成连续曲线。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("趋势")
    }
}
