<a id="english"></a>

# Stress Meter

[English](#english) | [简体中文](#chinese)

A standalone watch app with a Chinese interface for **Apple Watch Series 11 running watchOS 26 or later**. It reads heart rate variability (SDNN), heart rate, and workout records from Apple Health to show an experimental estimate of stress trends relative to your recent personal baseline.

The **grey tabby cat** on the dashboard expresses the estimate through its posture and gentle animations, alongside the level and the actual sample time.

| State | Grey tabby behavior |
| --- | --- |
| Lower | Stretches out, relaxes with closed eyes, and gently sways its tail |
| Usual | Sits comfortably, breathes steadily, and occasionally blinks |
| Elevated | Curls up slightly, lowers its ears, and tucks its tail in |
| No data, insufficient baseline, stale data, activity effects, or read failure | Uses a neutral waiting pose with an ellipsis and displays the specific reason |

The cat is drawn with native SwiftUI vector graphics. Its illustration updates at up to approximately 12 frames per second, only while the app is active and the cat is visible on the dashboard. It uses a static pose during reduced-luminance Always On display, Low Power Mode, Reduce Motion, navigation away from the page, or scrolling the cat out of view. The animation clock never triggers health data queries, and movement does not indicate a new measurement.

[Preview the four poses](docs/screenshots/tabby-poses.png)

## Open and run

1. Open `StressMeter.xcodeproj` in Xcode and select the **StressMeter** scheme.
2. Select an installed Apple Watch simulator and run the app. Tap **体验演示** (Try demo) to explore the interface. Demo mode is always labeled **演示 · 非健康数据** (Demo · Not health data).
3. To install on a physical watch, select your Apple Developer Team under **Signing & Capabilities**, replace `com.example.StressMeter` with your own unique Bundle Identifier, and retain the HealthKit capability and background delivery entitlement.
4. Connect the paired iPhone / Apple Watch through Xcode's Devices and Simulators, enable Developer Mode when prompted, select the watch as the run destination, and run the app.
5. On the watch, tap **连接健康数据** (Connect health data) and allow read access to heart rate, heart rate variability, and workouts. The app does not request write access.

Your account and provisioning profile must support HealthKit signing. The simulator has no real optical sensor data; a working demo and successful build do not establish stability on a physical Series 11.

You can also launch explicitly with `--demo`, which is useful for simulator screenshots. Demo mode is never enabled automatically when a live query fails or returns no data.

## Refresh frequency

| Situation | Behavior |
| --- | --- |
| Foreground, 07:00–22:59 | Targets a health record query every 5 minutes |
| Foreground, 23:00–06:59 | Targets a query every 10 minutes |
| Low Power Mode | Targets a query every 10 minutes |
| Returning to the foreground / manual refresh | Queries the currently available records |
| HealthKit change notification | Coalesces duplicate notifications and queries again |
| Background | Requests a refresh from watchOS; the system schedules delivery, potentially much later than the requested time |

These intervals describe **how often existing health records are queried**. The app cannot guarantee new HRV measurements at the same frequency and does not start artificial workout sessions to increase sampling or keep itself running. The dashboard shows the actual sample times for HRV and heart rate separately; the time of the last record query appears in Settings.

## How levels are calculated

- Compare the latest valid SDNN sample with records from the same source over the preceding 28 days.
- Require at least 20 baseline samples across at least 5 UTC dates. Exclude the current sample and the preceding 30 minutes from its own baseline.
- Exclude samples during known workouts and for 30 minutes afterward, and account for activity indicators on nearby heart rate samples.
- Take the natural logarithm of HRV and calculate `z = (baseline median − current value) / max(1.4826 × MAD, 0.15)` in log space. Display elevated for `z ≥ 1`, lower for `z ≤ −1`, and usual otherwise.
- Stop treating a sample as a current estimate once it is more than 20 minutes old. Insufficient baseline, activity effects, missing data, and read errors have distinct states.
- Show heart rate separately for context; it does not directly contribute to the stress level. Historical points use only earlier samples to build their baselines, and gaps are not interpolated.

These thresholds are **explicit, testable engineering rules that have not been clinically validated**. They describe relative HRV changes, not a stress percentage, and are not intended for diagnosis. Activity, posture, breathing, sleep, and individual differences can affect readings. The interface notes when activity context is limited.

## Data and privacy

There are no accounts, servers, analytics SDKs, or third-party runtime dependencies. Health records are processed only in memory on the watch. Each successful query replaces the entire snapshot so that deletions and access changes can be reflected in the interface. Only the monitoring-enabled preference is stored in UserDefaults; raw health data is not written to disk.

**暂停并清除本地结果** (Pause and clear local results) stops observation and clears the current in-memory results. Late asynchronous callbacks cannot restore old results. This does not delete records from Apple Health. Reconnecting queries the baseline again.

To protect privacy, HealthKit does not tell the app whether read access to a particular data type was denied. Empty results therefore appear as “No readable data currently available,” without incorrectly claiming that access was granted or denied.

## Tests and project structure

```sh
swift test --scratch-path /tmp/stress-meter-core-build
zsh scripts/test-health-provider.sh
xcodebuild -project StressMeter.xcodeproj -scheme StressMeter \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath /tmp/stress-meter-derived-data CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StressMeter.xcodeproj -scheme StressMeter \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /tmp/stress-meter-device-build CODE_SIGNING_ALLOWED=NO build
```

Keep build output under `/tmp`: some file providers for Documents attach Finder metadata to generated files, which can interfere with code signing for local test bundles.

- `Sources/StressCore/`: Pure Swift estimation, data quality rules, refresh policy, asynchronous monitoring state, and pet state / animation conditions.
- `Tests/StressCoreTests/`: Deterministic boundary and race-condition tests.
- `WatchApp/HealthKitProvider.swift`: Read-only HealthKit queries, timeouts, and observation.
- `WatchApp/AppModel.swift`: Foreground/background lifecycle and refresh scheduling.
- `WatchApp/Views/`: Native SwiftUI interface; `TabbyCatView.swift` contains the grey tabby drawing and foreground animation.
- [Verification record](docs/verification.md): Actual results and outstanding physical-device checks (in Chinese).
- [Design](docs/design/2026-09-26-watchos-stress-meter-proposal.md) · [Implementation plan](docs/superpowers/plans/2026-09-26-stress-meter-v1.md) (in Chinese).

## Official references and research

- [Apple: HRV SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn)
- [Apple: HealthKit background delivery](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:))
- [Apple: Health data authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Apple DTS: watchOS background limitations](https://developer.apple.com/forums/thread/816544)
- [Apple Watch stress detection pilot study](https://pmc.ncbi.nlm.nih.gov/articles/PMC9780663/)
- [Methodological guidance for HRV research and interpretation](https://pmc.ncbi.nlm.nih.gov/articles/PMC5316555/)

---

<a id="chinese"></a>

# 压力计 · Stress Meter

面向 **Apple Watch Series 11、watchOS 26 及以上**的独立中文手表应用。读取 Apple 健康中的心率变异性（SDNN）、心率和体能训练记录，展示相对于个人近期基线的实验性压力趋势。

首页的**灰狸花猫**用姿态与轻动画呈现估算结果，同时显示等级和真实样本时间。

| 状态 | 灰狸花猫的表现 |
| --- | --- |
| 偏低 | 舒展身体，闭眼放松，轻轻摆尾 |
| 平常 | 放松坐姿，平稳呼吸，偶尔眨眼 |
| 偏高 | 微微蜷起，耳朵稍垂，尾巴收拢 |
| 无数据、基线不足、过期、活动影响或读取失败 | 中性等待姿态和省略号，并显示具体原因 |

小猫使用原生 SwiftUI 矢量绘制。动画只在首页的小猫位于可见区域、应用活跃时播放，局部绘制最高约 12 帧/秒；常亮降亮度、低电量、减少动态效果、离开页面或滚动至看不到小猫时采用静态姿态。动画时钟不触发健康读取，动作变化不代表新测量。

[四种姿态预览](docs/screenshots/tabby-poses.png)

## 打开与运行

1. 用 Xcode 打开 `StressMeter.xcodeproj`，选择 **StressMeter** scheme。
2. 先选择一个已安装的 Apple Watch 模拟器，运行应用；点击「体验演示」查看完整界面。演示始终标记为「演示 · 非健康数据」。
3. 真机安装：在 **Signing & Capabilities** 选择自己的 Apple Developer Team，将 `com.example.StressMeter` 改为自己唯一的 Bundle Identifier，保留 HealthKit 能力与后台交付 entitlement。
4. 在 Xcode 的 Devices and Simulators 中连接已配对的 iPhone / Apple Watch，按系统提示开启开发者模式，选择手表作为运行目标，运行。
5. 在手表点击「连接健康数据」，选择允许读取心率、心率变异性、体能训练。应用不申请写入权限。

签名需要当前账号与 provisioning profile 支持 HealthKit。模拟器没有真实光学传感器数据；模拟器演示和成功构建不能证明 Series 11 真机稳定性。

也可用启动参数 `--demo` 显式进入演示，适合模拟器截图。它不会在真实查询失败或无数据时自动启用。

## 更新频率

| 情况 | 行为 |
| --- | --- |
| 前台 07:00–22:59 | 目标每 5 分钟重新读取健康记录 |
| 前台 23:00–06:59 | 目标每 10 分钟读取 |
| 低电量模式 | 目标每 10 分钟读取 |
| 进入前台 / 手动刷新 | 补查当前可读取记录 |
| HealthKit 通知新变化 | 合并重复通知并重新查询 |
| 后台 | 向 watchOS 请求刷新，由系统实际安排，可能明显晚于目标时间 |

这是**读取已有健康记录的频率**。应用不能保证相同频率产生新的 HRV，也不创建虚假的运动会话来提高采样或保活。首页显示 HRV 和心率各自的真实采样时间；「上次读取记录」单独放在设置页。

## 等级如何计算

- 以最新有效 SDNN 样本与同来源、过去 28 天的个人记录比较。
- 基线需要至少 20 条样本，分布在至少 5 个 UTC 日期；当前样本及之前 30 分钟不进入自身基线。
- 剔除已知运动期间及结束后 30 分钟的样本，并考虑邻近心率的活动标记。
- 对 HRV 取自然对数，计算 `z = (基线中位数 − 当前值) / max(1.4826 × MAD, 0.15)`。`z ≥ 1` 显示偏高，`z ≤ −1` 显示偏低，其余显示平常。
- 超过 20 分钟的样本不再作为当前估算；基线不足、活动影响、无数据和读取错误均有独立状态。
- 心率单独作为参考显示，不直接加入压力等级。历史点只使用该时刻之前的样本建基线，空档不插值。

这些阈值是**明确、可测试的工程规则，尚未经临床验证**。它们反映 HRV 相对变化，不是压力百分比，不用于诊断。活动、姿势、呼吸、睡眠和个体差异均可能影响读数；缺少活动情境时页面会提示参考有限。

## 数据与隐私

没有账户、服务器、分析 SDK 或第三方运行时依赖。健康记录只在手表内存中处理，每次成功查询替换整个快照，让删除与访问变化能反映到界面。仅「是否已启用监测」偏好存入 UserDefaults；应用不将原始健康数据写入磁盘。

「暂停并清除本地结果」会停止观察并清空当前内存结果，迟到的异步回调不能恢复旧结果。此操作不会删除 Apple 健康里的记录。再次连接会重新查询基线。

HealthKit 为保护隐私，不告知应用某项读取权限是否被拒绝，因此空结果显示「暂时没有可读取数据」，不错误断言「已授权」或「已拒绝」。

## 测试与工程结构

```sh
swift test --scratch-path /tmp/stress-meter-core-build
zsh scripts/test-health-provider.sh
xcodebuild -project StressMeter.xcodeproj -scheme StressMeter \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath /tmp/stress-meter-derived-data CODE_SIGNING_ALLOWED=NO build
xcodebuild -project StressMeter.xcodeproj -scheme StressMeter \
  -destination 'generic/platform=watchOS' \
  -derivedDataPath /tmp/stress-meter-device-build CODE_SIGNING_ALLOWED=NO build
```

建议将构建输出放在 `/tmp`：部分 Documents 文件提供程序会给生成文件附加 Finder 元数据，干扰本地测试 bundle 的代码签名。

- `Sources/StressCore/`：纯 Swift 估算、数据质量、刷新策略、异步监测状态及宠物状态/动画条件。
- `Tests/StressCoreTests/`：确定性的边界与竞态测试。
- `WatchApp/HealthKitProvider.swift`：只读 HealthKit 查询、超时和观察。
- `WatchApp/AppModel.swift`：前后台生命周期和刷新调度。
- `WatchApp/Views/`：原生 SwiftUI 界面；`TabbyCatView.swift` 包含灰狸花猫绘制及前台动画。
- [验证记录](docs/verification.md)：实际执行结果及待完成的真机项目。
- [设计](docs/design/2026-09-26-watchos-stress-meter-proposal.md) · [实现计划](docs/superpowers/plans/2026-09-26-stress-meter-v1.md)

## 官方参考与研究

- [Apple：HRV SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn)
- [Apple：HealthKit 后台交付](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:))
- [Apple：健康数据授权语义](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Apple DTS：watchOS 后台限制](https://developer.apple.com/forums/thread/816544)
- [Apple Watch 压力识别试点研究](https://pmc.ncbi.nlm.nih.gov/articles/PMC9780663/)
- [HRV 研究与解释的方法学建议](https://pmc.ncbi.nlm.nih.gov/articles/PMC5316555/)
