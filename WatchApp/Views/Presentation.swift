import Foundation
import SwiftUI
import StressCore

enum Palette {
    static let mint = Color(red: 0.48, green: 0.89, blue: 0.73)
    static let lavender = Color(red: 0.73, green: 0.68, blue: 1)
    static let amber = Color(red: 1, green: 0.75, blue: 0.42)
    static let panel = Color.white.opacity(0.075)
}

extension PetMood {
    var poseDescription: String {
        switch self {
        case .relaxed: "身体舒展"
        case .balanced: "放松坐姿"
        case .tense: "微微蜷起，耳朵稍垂"
        case .waiting: "等待有效数据"
        }
    }
}

extension StressLevel {
    var title: String {
        switch self { case .lower: "偏低"; case .usual: "平常"; case .elevated: "偏高" }
    }
    var tint: Color {
        switch self { case .lower: Palette.mint; case .usual: Palette.lavender; case .elevated: Palette.amber }
    }
    var symbol: String {
        switch self { case .lower: "leaf"; case .usual: "waveform.path"; case .elevated: "waveform.path.ecg" }
    }
}

extension Assessment {
    var title: String {
        switch state {
        case .noData: "等待数据"
        case .calibrating: "建立基线"
        case .stale: "待更新"
        case .activity: "活动影响"
        case .ready: level?.title ?? "等待数据"
        }
    }
    var explanation: String {
        switch state {
        case .noData: "暂时没有可读取的 HRV 数据。可稍后重试，或检查健康数据访问。"
        case .calibrating: "需要至少 5 天、20 条可用历史样本，才显示个人趋势。"
        case .stale: "最近样本已超过 20 分钟，当前状态暂不估算。"
        case .activity: "活动或运动后恢复可能影响读数，暂不估算压力。"
        case .ready: "相对个人近期基线的估算，不等同于直接测量心理压力。"
        }
    }
    var tint: Color { state == .ready ? (level?.tint ?? .secondary) : .secondary }
}

func ageText(_ date: Date?, now: Date) -> String {
    guard let date else { return "尚无样本" }
    let age = now.timeIntervalSince(date)
    guard age >= 0 else { return "时间待校准" }
    if age < 60 { return "刚刚" }
    if age < 3_600 { return "\(Int(age / 60)) 分钟前" }
    if age < 86_400 { return "\(Int(age / 3_600)) 小时前" }
    return "\(Int(age / 86_400)) 天前"
}

struct DemoBadge: View {
    var body: some View {
        Label("演示 · 非健康数据", systemImage: "play.rectangle")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.amber)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .background(Palette.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }
}
