import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var showingClear = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.isDemo { DemoBadge() }
                Text("随时段调整").font(.headline)
                Text("前台日间约 5 分钟、23:00 至 07:00 约 10 分钟读取一次。低电量模式约 10 分钟。")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("当前目标：\(model.intervalMinutes) 分钟")
                    .font(.footnote).foregroundStyle(Palette.mint)
                Text("后台由系统安排，实际可能更久。刷新健康记录不等于启动一次新的心率变异性测量。")
                    .font(.caption2).foregroundStyle(.secondary)
                if let date = model.lastReadDate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("上次读取记录").font(.caption2).foregroundStyle(.secondary)
                        Text(date, style: .time).font(.footnote.monospacedDigit())
                        Text("生理样本的采样时间请查看首页。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let notice = model.backgroundNotice {
                    Text(notice).font(.caption2).foregroundStyle(Palette.amber)
                }
                NavigationLink("估算方式与数据访问") { MethodView(isDemo: model.isDemo) }
                    .font(.footnote)
                if model.isDemo {
                    Button("连接真实健康数据") {
                        Task { await model.startLive(); dismiss() }
                    }.disabled(model.isConnecting || model.session.isRefreshing)
                }
                Button(role: .destructive) { showingClear = true } label: {
                    Text(model.isDemo ? "退出演示" : "暂停并清除本地结果")
                }
                .font(.footnote)
                Text("不会删除 Apple 健康中的记录。应用不保存原始健康数据到磁盘。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .navigationTitle("设置")
        .confirmationDialog("暂停监测并清除当前结果？", isPresented: $showingClear) {
            Button("确认清除", role: .destructive) { model.stopAndClear(); dismiss() }
            Button("取消", role: .cancel) {}
        }
    }
}

struct MethodView: View {
    var isDemo: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isDemo { DemoBadge() }
                section("个人参照", "比较最新 HRV（SDNN）与过去 28 天同来源的历史水平。至少积累 5 天、20 条可用样本后才显示等级。")
                section("压力趋势估计", "偏高、平常、偏低是实验性的相对等级，没有经过临床验证。心率作为参考单独显示，不直接等同于心理压力。")
                section("数据何时有效", "HRV 超过 20 分钟不作为当前估算。已知运动或运动后 30 分钟内暂缓估算；缺少活动情境时会提示参考有限。这些是工程规则，不是医学界限。")
                section("读数为什么不同", "活动、呼吸、姿势、疲劳及个体差异都可能影响 HRV。一次偏高不能诊断焦虑或其他疾病。")
                section("没有可读取数据", "可能尚未产生记录，也可能没有读取权限。请在 iPhone 健康 App 的个人资料 → App 与服务中找到压力计，检查心率、心率变异性和体能训练的访问。系统版本不同，入口名称可能不同。")
                section("隐私", "只读健康数据，只在手表本地处理，不上传、不写入健康记录。暂停并清除会移除当前内存中的结果，重新连接后会重新读取。")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .navigationTitle("说明")
    }

    private func section(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline).foregroundStyle(Palette.mint)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
