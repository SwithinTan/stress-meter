import SwiftUI
import StressCore

struct DashboardView: View {
    @Bindable var model: AppModel

    private var assessment: Assessment { model.assessment }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if model.isDemo { DemoBadge() }
                Text("压力趋势 · 估计")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                gauge
                Label(ageText(assessment.sampleDate, now: model.now), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("最近 HRV 样本，\(ageText(assessment.sampleDate, now: model.now))")
                if let error = model.session.errorMessage {
                    Label("读取未完成", systemImage: "exclamationmark.circle")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.amber)
                    Text(error).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(assessment.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(alignment: .top, spacing: 6) {
                    metric("HRV", value: assessment.hrv, unit: "ms", date: assessment.sampleDate)
                    metric("心率", value: assessment.heartRate?.value, unit: "次/分", date: assessment.heartRate?.date)
                }
                if assessment.state == .calibrating {
                    Text("已获得 \(assessment.baselineCount) 条 · \(assessment.baselineDays) 天")
                        .font(.caption2).foregroundStyle(Palette.lavender)
                } else if assessment.state == .ready && assessment.contextLimited {
                    Text("活动情境有限 · 仅供参考")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                    Task { await model.refresh() }
                } label: {
                    HStack {
                        if model.session.isRefreshing { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text(model.session.isRefreshing ? "正在读取" : "刷新健康记录")
                    }.font(.footnote)
                }
                .disabled(model.session.isRefreshing || !model.session.isMonitoring)
                NavigationLink { TrendView(model: model) } label: {
                    Label("近 7 天趋势", systemImage: "chart.dots.scatter")
                        .font(.footnote)
                }
                NavigationLink { SettingsView(model: model) } label: {
                    Label("设置与说明", systemImage: "slider.horizontal.3")
                        .font(.footnote)
                }
                Text("有新样本时更新 · 实验性")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
    }

    private var gauge: some View {
        ZStack {
            Circle().trim(from: 0.12, to: 0.88)
                .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(90))
            if assessment.state == .ready, let level = assessment.level {
                Circle().trim(from: 0.12, to: arcEnd(level))
                    .stroke(level.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(90))
            }
            VStack(spacing: 6) {
                Image(systemName: assessment.state == .ready ? (assessment.level?.symbol ?? "waveform.path") : "ellipsis")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(assessment.tint)
                Text(model.session.errorMessage == nil ? assessment.title : "待重试")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text("相对个人基线")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
        }
        .frame(width: 132, height: 88)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("压力趋势估计，\(model.session.errorMessage == nil ? assessment.title : "读取失败")")
    }

    private func arcEnd(_ level: StressLevel) -> CGFloat {
        switch level { case .lower: 0.32; case .usual: 0.59; case .elevated: 0.88 }
    }

    private func metric(_ name: String, value: Double?, unit: String, date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                    .font(.title3.monospacedDigit().weight(.medium))
                Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Text(ageText(date, now: model.now)).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
