import SwiftUI
import StressCore

struct DashboardView: View {
    @Bindable var model: AppModel

    private var assessment: Assessment { model.assessment }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                if model.isDemo { DemoBadge() }
                Text("压力伙伴 · 估计")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                pet
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

    private var pet: some View {
        let hasReadError = model.session.errorMessage != nil
        let mood = PetMood(assessment: assessment, hasReadError: hasReadError)
        return VStack(spacing: 0) {
            TabbyCatView(mood: mood)
                .frame(width: 150, height: 68)
            Text(hasReadError ? "待重试" : assessment.title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(hasReadError ? .secondary : assessment.tint)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("灰狸花猫，\(mood.poseDescription)。压力趋势估计，\(hasReadError ? "读取失败，待重试" : assessment.title)")
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
