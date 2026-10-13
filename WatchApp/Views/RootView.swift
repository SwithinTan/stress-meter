import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.hasStarted || model.isDemo {
                    DashboardView(model: model)
                } else {
                    WelcomeView(model: model)
                }
            }
            .navigationTitle("压力计")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

private struct WelcomeView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Palette.mint)
                    .frame(width: 42, height: 42)
                    .background(Palette.mint.opacity(0.1), in: Circle())
                    .accessibilityHidden(true)
                Text("感受自己的节奏")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("从心率变异性了解近期压力趋势。以你的日常水平为参照。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let error = model.session.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(Palette.amber)
                }
                Button {
                    Task { await model.startLive() }
                } label: {
                    if model.isConnecting || model.session.isRefreshing { ProgressView() }
                    else { Text("连接健康数据") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isConnecting || model.session.isRefreshing)
                Button("体验演示") { Task { await model.startDemo() } }
                    .buttonStyle(.bordered)
                    .disabled(model.isConnecting || model.session.isRefreshing)
                NavigationLink("了解估算方式") { MethodView(isDemo: false) }
                    .font(.footnote)
                Text("只读访问 · 本地处理\n实验性趋势，不用于诊断")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 12)
        }
    }
}
