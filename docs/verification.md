# 验证记录

更新：2026-10-12。状态：第一版代码、自动化检查和本地构建已完成；实体 Series 11 验收尚未执行。

## 开发环境

- Xcode 27.0（27A266a），watchOS / WatchSimulator 27.0 SDK。
- CoreSimulator 已安装；创建并运行了 Series 11 42mm / 46mm 模拟设备，运行时为 watchOS 27.0。
- 本轮设备列表中没有可用的实体 Apple Watch；Series 11 项目的 Reality 字段为 simulated。
- 目标最低 watchOS 26；当前只使用 watchOS 27 SDK/运行时完成本地验证，尚未在 watchOS 26 实机运行。

## 自动化验证

| 检查 | 2026-10-12 结果 |
| --- | --- |
| `swift test --scratch-path /tmp/stress-meter-final-core` | 30 项 XCTest，0 失败 |
| `zsh scripts/test-health-provider.sh` | 5 项生命周期检查通过 |
| generic watchOS Simulator 构建，关闭签名 | exit 0，BUILD SUCCEEDED |
| generic watchOS 构建，关闭签名 | exit 0，BUILD SUCCEEDED |
| 编译产物与配置 | 两个 app 均有非空 Mach-O 可执行文件、资源和与源文件相符的隐私清单 |
| Plist 与 staged diff 格式 | plist 校验通过；diff 无空白错误 |

两次构建仅出现 AppIntents metadata extraction skipped 提示，应用没有 AppIntents 功能；无编译错误。设备构建架构为 arm64 / arm64_32，模拟器为 x86_64 / arm64。两个包的最低系统为 26.0，均为独立 watch-only 应用，显示名为「压力计」。

```sh
xcodebuild -project StressMeter.xcodeproj -scheme StressMeter \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath /tmp/stress-meter-final-simulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StressMeter.xcodeproj -scheme StressMeter \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /tmp/stress-meter-final-device CODE_SIGNING_ALLOWED=NO build
```

本机原始日志与产物核查记录保存在 `.artifacts/verification/`（git 忽略）：`core-tests.log`、`watchos-device-build-2026-10-12.log`、`watchos-simulator-build-2026-10-12.log` 和 `bundle-verification-2026-10-12.json`。

核心测试覆盖个人基线、来源隔离、无效值、重复记录、删除后的快照替换、过期、活动影响、历史不使用未来基线、时区和低电量策略、并发刷新合并、授权/查询中暂停及迟到回调。查询检查覆盖启动前取消、超时、进行中取消、重复完成和 observer 完成一次。

## 模拟器界面与独立审查

2026-09-26 已在 Series 11 两种尺寸的模拟设备安装并启动应用，检查欢迎页及显式演示首页，调整 42mm 首页使等级和样本年龄可见：

- [42mm 演示首页](screenshots/series11-42mm-demo.png)
- [46mm 演示首页](screenshots/series11-46mm-demo.png)
- [42mm 欢迎页](screenshots/series11-42mm-welcome.png)

独立审查发现并修复了冷启动观察器注册遗漏、历史页与首页的活动过滤不一致、过长的后台完成期限以及测试脚本 shell 文档错误。历史过滤有先失败后通过的回归测试；修复后的限定范围复审未发现新的可操作问题。

尚未进行真实健康授权交互、真实传感器读取、完整界面自动化或辅助功能真机验收。当前证据证明代码可构建、核心规则经过测试及首页可在模拟器运行，不证明实体设备的交付频率或全天稳定性。

## Series 11 真机验收（尚未执行）

- [ ] 记录硬件尺寸、watchOS 版本、iPhone / iOS 版本和应用提交版本。
- [ ] 允许全部读取、仅部分读取、拒绝读取、随后撤销读取；无数据不误显示为平静。
- [ ] 已有健康历史能建立基线，新用户准确显示基线不足。
- [ ] 对照 Apple 健康，核对 HRV 单位、采样时间和来源；区分数据库交付延迟与传感器采样间隔。
- [ ] 抬腕、息屏、按表冠离开、重新进入、系统回收及重启后状态正常。
- [ ] 运动及运动结束后恢复期不显示心理压力判定；与系统体能训练正常并存。
- [ ] 低电量、跨越 07:00 / 23:00、更改时区和时钟；不会误刷新样本时间。
- [ ] 在查询中暂停清除，等待后也不恢复旧结果；重新连接可正常读取。
- [ ] 连续佩戴至少 24 小时，记录崩溃、卡死、后台实际回调间隔和样本陈旧时间。
- [ ] 与不启用应用的相近使用日对照耗电，记录佩戴、运动、常亮屏与网络条件。
- [ ] 两种尺寸和较大辅助功能字体可滚动、可读，VoiceOver 能读出数据状态。

通过模拟器或单元测试不代表估算获得临床验证，也不代表全天真机稳定性已获得验证。
