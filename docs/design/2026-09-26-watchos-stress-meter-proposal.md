# Stress Meter：Apple Watch Series 11 开发方案草案

日期：2026-09-26。状态：用户已确认方向 A 并授权开发；第一版代码和本地验证已完成，Series 11 真机验证尚未完成。记录更新：2026-10-12。

## 目标与暂定范围

用户要求：开发在 Apple Watch Series 11 的 watchOS 上稳定运行、显示实时压力水平的应用。

暂定使用情境：日常自用、中文界面、优先稳定与续航。这里的“11代”按 Series 11 硬件理解，不等同于 watchOS 11。软件最低部署版本拟为 watchOS 26；安装前确认手表实际系统版本和开发工具兼容性。

用户已确认：不需要全天后台逐秒更新，可按时段动态调整到几分钟至约 10 分钟。前台默认日间 5 分钟、夜间 10 分钟重新查询，有新样本立即更新；后台间隔为请求目标，不保证系统按此频率唤醒或产生新样本。

## 已核实的技术边界

- HealthKit 提供心率、HRV 等数据。SDNN HRV 是系统自动记录的离散样本；应用需要自行推算压力趋势，不能称为 Apple 官方压力测量。[SDNN 文档](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn)
- 2026 年更新的 Apple 心率说明将全天连续采样的新能力列于 Series 12 / Ultra 4，不能直接套用到 Series 11。[Apple 心率说明](https://support.apple.com/en-us/120277)
- 后台 HealthKit 数据交付受 watchOS 调度和频率限制；注册 observer 或请求 immediate 不会启动传感器，也不保证持续实时交付。[后台交付 API](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:))
- 正念 extended runtime 提供有限的运行时间，不能据此保证实时 HRV。非运动应用借 workout session 长期保活有审核风险。[Extended runtime](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions)、[Apple DTS 说明](https://developer.apple.com/forums/thread/816544)
- 表盘复杂功能由 WidgetKit 调度，展示最近结果与时间，不能承诺秒级刷新。[WidgetKit 更新机制](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- HealthKit 空查询可能表示无数据或无读取权限；不能将授权请求成功解释为读取权限全部获准，也不能用写入授权状态判断读取权限。[授权语义](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- watchOS 27 提供 RMSSD 符号，但现有文档不足以确认 Series 11 自动产生该数据。第一版使用 SDNN；未来若引入 RMSSD，独立建立基线，不能与 SDNN 混算。[RMSSD 文档](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilityrmssd)

## 可选方向

| 方向 | 行为 | 取舍 |
| --- | --- | --- |
| A：日常趋势，推荐 | 利用系统现有样本，打开应用补查；得到新数据后立即更新 | 续航优先，更新间隔由系统与样本决定 |
| B：静坐观察 | 用户主动进入短时观察或真实正念引导，同时读取可获得的新数据 | 增加交互体验，但无法保证比 A 产生更多 HRV 样本 |
| C：运动期间监测 | 真实运动会话中读取较密集的心率 | 适用于运动负荷；生理变化难直接解释为心理压力，不适合当前默认场景 |

建议先实现 A。B 可在后续加入；不将 C 作为日常压力监测的保活手段。

## 第一版体验

1. 首次打开：说明数据用途，申请只读健康权限；不要求账户，不上传健康数据。
2. 主屏：大号相对压力趋势、最近样本时间、数据可用状态；可查看心率与 HRV 的各自时间。
3. 明确状态：正在读取、建立基线、存在近期估算、数据过期、暂时没有可读取数据、活动可能影响结果、读取发生错误。
4. 趋势页：显示实际观测点与时间；数据空档保留，不插值制造连续压力曲线。
5. 刷新按钮：重新查询健康数据；文案说明它不保证触发新测量。
6. 方法页：说明估算依据、局限及如何在系统设置检查健康数据访问。

表盘复杂功能作为第一版之后的增量：小屏显示最近结果和数据年龄，点击打开主应用。在主体采样、状态处理和耗电验证完成后加入。

## 估算与呈现原则

HRV 与心理压力存在研究关联，但会受到活动、呼吸、姿势和个体差异等影响。已有 Apple Watch 试点研究不能直接验证本项目的被动采样算法。[Apple Watch 试点研究](https://pmc.ncbi.nlm.nih.gov/articles/PMC9780663/)、[HRV 方法学建议](https://pmc.ncbi.nlm.nih.gov/articles/PMC5316555/)

第一版应显示“压力趋势估计（实验性）”，以相对于个人近期基线的变化为依据。未经独立验证，不给出“压力百分比”或准确率承诺，不将统一 HRV 毫秒阈值应用于所有人。实现规划中需明确可复现的工程阈值和数据有效期；这些参数属于待验证的产品规则，不是医学界限。

基线不足时展示原始可用指标及“正在建立基线”，不硬算压力。已知运动、明显活动或不合适的测量情境下暂缓估算；情境未知时说明参考有限。无新样本不更新时间戳，过期值只作为历史记录，不能显示为当前状态，也不能回落成“0／平静”。

可以在后续引入用户自评用于验证，但不能把传感器推算描述成比用户自己的感受更准确。

## 技术结构

- **原生 watchOS 界面**：SwiftUI，适配 Series 11 两种屏幕尺寸与辅助功能字号。
- **健康数据读取层**：负责 HealthKit 授权请求、查询、增删变化与前台补查；对每项数据保留来源、类型、单位与时间。
- **纯 Swift 估算模块**：输入规范化样本与当前时间，输出趋势、数据质量状态及理由；与 HealthKit、UI 分离，便于本机测试。
- **应用状态层**：统一加载、可用、过期、无数据及错误状态，避免多个异步回调覆盖较新的结果。
- **本地数据**：基线和历史结果仅在内存中保留，查询容量有界；提供暂停清除功能，完整替换查询快照以支持健康数据删除后的重算。仅监测启用偏好写入磁盘。
- **生命周期处理**：进入前台补查；停止不需要的查询；后台工作有界且正确结束回调；不依赖高频轮询或后台常驻。

演示数据与真实数据必须完全分离。模拟器演示应常驻“演示数据”标记，不能在读不到真实数据时自动切入演示。

## 验证与交付标准

| 层级 | 验证内容 | 通过后可作出的结论 |
| --- | --- | --- |
| 纯 Swift | 空数据、异常值、重复/乱序/删除样本、过期、基线不足、活动干扰、时钟变化 | 计算与状态规则按设计工作 |
| watchOS 构建与模拟器 | SDK/API 可用性、签名配置之外的编译、两种尺寸排版、权限和空态流程 | 应用可构建，界面基本流程可验证 |
| Series 11 真机 | 真实授权与采样、抬腕/息屏、前后台、重启、低电量模式、撤销权限、与运动应用并存 | 记录设备及系统版本下的实际表现 |
| 连续佩戴测试 | 至少 24 小时的崩溃/卡死、样本与交付间隔、数据陈旧状态、耗电对照 | 对该测试条件下的稳定性给出有证据的报告 |

“稳定运行”以真机测试记录为依据；本机单元测试或模拟器通过不足以证明全天稳定或心理压力估算准确。

交付目标：原生工程、纯 Swift 模块与测试、中文使用说明、签名安装步骤，以及明确区分已通过与待完成项目的验证记录。

## 当前开发环境与执行状态

用户已安装 Xcode 和 CoreSimulator。当前 Xcode 27.0 提供 watchOS 27 SDK，模拟器可列出设备；现有运行时包含 Series 12 的 42/46mm 和 SE 3，不能替代 Series 11 真机验证。

用户已批准方案并明确授权开发。实现、独立审查和本地验证已执行，具体结果见 `../verification.md`。已创建 Series 11 42/46mm 模拟器用于界面验证；它们不代表实体手表测试。
