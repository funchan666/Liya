<!-- appstore-review-audit-report:v1 -->
# App Store 首审风险审计

项目：Liya

审计日期：2026-11-09；技能版本：1.2.0

版本/工作区：master 433a12bffcadd4ef792f43bf67fe745c47e32849；审计前工作区干净

Target：Liya iOS SwiftUI；Bundle ID com.liyalumora.auroramuse；版本 1.0；配置：按 Xcode 项目 Release 配置及项目源码静态检查；实际提交 scheme、storefront 和最终归档未知

审计范围：当前项目 Swift、Xcode 配置、Supabase functions 与 migrations、协议文本；没有现成 IPA、app、Archive 或匹配 Mach-O；未查线上服务及 ASC。P1 专项只读审查，不运行项目脚本、编译、测试或启动。

规则核验：部分在线核验；日期：2026-11-09

> 本报告由已脱敏的输入生成。渲染成功仅说明数据形状有效，不证明证据真实、条款适用或能够过审；渲染器不代替脱敏检查。

## 结论

1 项已确认 P1：面向真实用户的社区举报与支持页面声明处理和支持渠道未配置；另有 1 项潜在 P1：Apple 登录账号删除未见撤销 Apple 凭证，需核查实际服务。未发现已确认 P0。结论仅覆盖源码及本地资料，不能证明线上或提交包状态。

活跃风险共 2 项（P0：0，P1：2，P2：0，P3：0）。

其中已确认 1 项；高度疑似 0 项；待核验 1 项。

历史项目 0 项、代码外待补证 6 项，均不计入上述活跃风险数。

## 覆盖范围

- 发布配置 · 待补证：核对 pbxproj、project.yml、Info.plist、entitlements；实际 Release 归档、版本 build、scheme、storefront、签名及最终合并配置未知。
- 启动与完整性 · 待补证：静态追踪 RootView 和登录入口；设备、邮件、服务可用性、审核账号未验证。
- 账号和删除 · 待补证：追踪设置、LiyaSession 和本地删除函数；Apple 撤销、线上部署和数据级联需要证据。
- 隐私与 AI · 待补证：追踪 AI 同意、Groq 转发与权限文案；ASC 隐私问卷、线上策略和最终 manifest 未验证。
- 支付 · 待补证：追踪 StoreKit 2、账户绑定、服务端验签、重复交付与 finish；ASC 商品、开关状态和沙盒/生产到账未验证。
- UGC 内容安全 · 待补证：追踪发布、读回、举报、拉黑、帮助及本地 migrations；实际过滤、运营工具、响应时间、服务端部署与联系渠道未验证。
- 远程行为与示例内容 · 待补证：检查示例资料、消息、云目录及服务开关；线上内容、版权与用户实际展示一致性需核验；未确认审核差异分流。
- 依赖与平台 API · 待补证：查看 Xcode 和 SPM 依赖；无法验证最终第三方 SDK、manifest、签名、静态链接及私有 API。
- 提交包与逆向 · 待补证：工作区内未发现 IPA、app、xcarchive、framework 或 dylib；REA MCP 工具可发现，但无匹配发布二进制，未打开分析；Hopper 未执行，架构与加密未知。
- iPhone Duo · 待补证：源码可见 DuoControlRegion 的 reserved region 分支及部分 safe area；未编译，未验证 SDK 可用性、键盘、切屏、播放或设备姿态，非完整视觉审计。
- 产品、版权与提交材料 · 待补证：素材权属、截图描述、年龄分级、隐私声明、审核账号及 ASC 商品配置未提供；不能推断已完成。

“已检查”表示完成所述范围的检查，不是认证通过。

## 官方来源核验记录

仅获取页面或 HTTP 请求成功不等于已阅读并核验。

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)；日期：2026-11-09；状态：已阅读并核验；范围：已阅读 1.2、2.1、5.1.1 和 5.1.2 对本次发现的相关正文
- [Account deletion](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)；日期：2026-11-09；状态：已阅读并核验；范围：账号删除与 Sign in with Apple 撤销指引
- [Complete Review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)；日期：2026-11-09；状态：已阅读并核验；范围：审核账号与外部服务资料
- [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)；日期：2026-11-09；状态：已阅读并核验；范围：每种类型首个内购与 App 版本提交条件
- [iPhone Duo adaptive layouts](https://developer.apple.com/videos/play/tech-talks/111463/)；日期：2026-11-09；状态：已阅读并核验；范围：布局区域与可达性设计建议

## 活跃风险

### AR-001 · P1 · 真实社区的举报处理与支持渠道仍标示未配置

状态：已确认；置信度：高；领域：UGC 内容安全

发布路径：RootView 社区路径 → SocialStore 发布和读取 liya\_posts → CommunityPostCard/CommunityReportView → liya\_social\_reports；设置 Help &amp; legal → Help &amp; Support。源码均属于主 App 源目录，未见仅 Debug 限制。

触发条件：用户在社区发布内容，其他用户举报帖子或成员，或尝试联系支持。

影响：App 明确告诉用户举报审核和支持尚未配置；保存举报不等于能及时响应。该社交产品的 UGC 安全闭环存在重大提审风险。

证据：

- code · Liya/Sources/RootView.swift:70 — 登录后包含 Square 等主 tab 并初始化社区数据。
- code · Liya/Sources/SocialStore.swift:227 — 社区内容带文字及附件写入云端帖子并刷新。
- code · Liya/Sources/SocialViews.swift:184 — 他人社区帖子提供举报入口。
- code · Liya/Sources/SocialViews.swift:421 — 举报页声明审核团队尚未配置，成功后仍声明 review is not yet configured。
- code · Liya/Sources/SocialStore.swift:367 — 举报写入表并回读以确认保存；本路径不证明人工处理。
- code · Liya/Sources/ProfileViews.swift:629 — 帮助页显示支持渠道尚未配置。
- metadata · docs/BackendAPI/legal/terms.md:15 — 本地条款亦说明举报审核尚未配置；公开文档线上状态未复验。

适用规则：

- [1.2 User-Generated Content](https://developer.apple.com/app-store/review/guidelines/)；核对日期：2026-11-09；适用性：真实用户发布及互动适用：要求不良内容过滤、举报和及时响应、拉黑与公开联系信息。

整改步骤：

1. 客户端/运营：建立真实可达支持渠道及举报接收、分派、响应和处置流程；在流程实际可用后更新页面和协议文案。
2. 后台/运营：建立适用于文字、图片、视频及评论的可执行过滤与违规内容下架机制，并明确时限、责任人与记录；保留有效拉黑。

验证步骤与预期结果：

1. 用两个真实测试账号提交违规样例并举报，验证运营收到、及时处置、内容对其他账号不可见及举报结果可追踪。
2. 验证支持渠道实际收发，并用测试内容核对过滤、拉黑和网络失败重试；复查提交包和线上协议。

负责模块/角色：客户端、后台、社区运营与支持；工作量：M–L；取决于现有运营系统和过滤服务

剩余不确定性：

- 未查看生产后台；可能已有外部运营流程，但本次未见证据，且当前页面仍明确提示未配置。
- 源码直接上传与数据库约束未体现内容审核；生产端是否存在独立过滤服务尚未验证。

### AR-002 · P1 · Apple 登录账号删除未见 Apple 凭证撤销

状态：待核验；置信度：中；领域：账号和隐私

发布路径：WelcomeView 使用 Sign in with Apple → LiyaSession.appleSignIn → 设置中删除账号 → liya-delete-account。

触发条件：用户通过 Apple 创建账号后在 App 内删除账号，且线上没有额外的 Apple token 撤销流程。

影响：如果删除仅执行仓库内代码，Apple 登录授权可能仍未撤销，与 Apple 的账号删除指引存在高风险差距。

证据：

- code · Liya/Sources/RootView.swift:175 — 使用 Apple 授权，读取 identityToken；此路径未发现用于后续撤销的 authorizationCode 处理。
- code · Liya/Sources/ProfileViews.swift:733 — 设置确认后调用 deleteAccount。
- code · Liya/Sources/LiyaSession.swift:316 — 客户端调用 liya-delete-account 并在确认成功后清理本地会话。
- code · supabase/functions/liya-delete-account/index.ts:48 — 函数移除用户媒体后调用 Supabase admin.deleteUser；整个函数未包含 Apple token 撤销调用。
- search\_scope · Liya、supabase、docs — 对 Apple revoke、authorizationCode、refresh token、通知等词检索；未检查托管 Supabase 内部实现或独立服务。

适用规则：

- [5.1.1\(v\) Sign in with Apple account deletion](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion)；核对日期：2026-11-09；适用性：Apple 指引称使用 Apple 登录的 App 应通过 Sign in with Apple REST API 撤销用户 token。

整改步骤：

1. 核查托管 Auth 和其他服务是否已实际撤销；若未覆盖，安全地接入 Apple 授权码交换、服务端凭证保存及撤销，确保失败可重试并避免提前声称完整删除。

验证步骤与预期结果：

1. 使用专门的 Apple 测试账号完成授权与删除，核对服务端撤销结果、账号数据删除及重试过程；核对失败、超时和重复请求。

负责模块/角色：身份认证后台与 iOS 客户端；工作量：M；取决于现有服务与 Apple 凭证配置

剩余不确定性：

- 线上托管认证服务或仓库外服务可能另行处理，尚未取得部署与运行证据；该项不计入已确认 P1 数量。

## 代码外待补证

优先级表示潜在影响，以下缺口不是已确认风险。

### GAP-001 · P1

真实 Release 包是否与此源码一致并包含可读主程序和 SDK？

需要的证据：提供拟提交 IPA、Archive 或 app 及版本/build；按架构检查加密、哈希，使用 REA MCP 的 Hopper 后端复核。

负责角色：发布负责人

### GAP-002 · P1

审核账号、邮箱与 Apple 登录以及生产服务是否可被审核人员使用？

需要的证据：可用的审核账号与审核说明；设备上验证邮件确认、密码重置、Apple 登录及服务可达。

负责角色：认证/ASC 负责人

### GAP-003 · P1

消耗型内购在 ASC 与服务器均已配置并可可靠交付？

需要的证据：对应商品及首个类型与版本同批提交记录、服务开关、沙盒购买/未完成交易重试/到账和退款处理验证。

负责角色：支付后台与 ASC 负责人

### GAP-004 · P1

示例资料、视频和本地消息在真实体验中是否清楚标明为示例及不可送达，素材是否获授权？

需要的证据：实际 Release 页面、视频目录、素材授权及真实用户路径截图或录屏；检查 App Store 元数据。

负责角色：产品与内容负责人

### GAP-005 · P1

AI 同意及数据流、隐私清单、ASC 问卷与实际服务是否一致？

需要的证据：线上部署与隐私配置、服务商数据处理信息、Release 隐私报告及 ASC 问卷。

负责角色：隐私与后台负责人

### GAP-006 · P2

Duo 及普通设备的布局和状态连续性是否可用？

需要的证据：获授权后使用实际支持 SDK 和设备/模拟器检查开合、左右分屏、安全区、键盘、导航、播放及通话连续性。

负责角色：iOS 客户端

## 已解决与不适用历史

本次无历史项目。
