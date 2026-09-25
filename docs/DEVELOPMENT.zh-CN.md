# 开发说明

[English](DEVELOPMENT.md) · [README](../README.zh-CN.md) · [隐私说明](PRIVACY.zh-CN.md)

## 本地构建

需要 macOS 14 及以上、提供 Swift 5.9+ 的 Apple Command Line Tools，以及 macOS 14+ SDK。项目使用 Swift Package Manager 和系统框架，无第三方依赖。本地构建无需 Xcode 工程或付费 Apple Developer 账号。

```bash
bash scripts/test.sh
bash scripts/build.sh
open dist/AgentMeter.app
```

`scripts/test.sh` 执行 `swift run MeterChecks` 检查核心行为，执行 `swift run MeterProviderChecks` 检查 Codex/Claude 适配器，并执行 `swift run AgentMeter --self-check` 检查应用模型集成。各项均使用离线样本；应用模型检查使用临时偏好设置域与模拟适配器。`scripts/build.sh` 创建应用包、用 AppKit 绘制图标、复制许可证说明、签名，并校验签名与 `Info.plist`。调试构建可使用 `CONFIGURATION=debug bash scripts/build.sh`。

## 架构

| 目录或文件 | 职责 |
| --- | --- |
| `Sources/MeterCore` | 订阅与额度公共模型、响应解析、数据新鲜度策略、按币种汇总、版本比较 |
| `Sources/MeterProviders` | 本地 Codex app-server 与 Claude 凭据、HTTP 适配器 |
| `Sources/AgentMeter/AppModel.swift` | 刷新调度、本地存储、演示数据隔离、手动更新检查 |
| `Sources/AgentMeter/Views` | 原生 SwiftUI 总览、简洁菜单栏额度面板、订阅管理与设置 |
| `Tests/MeterChecks` | 核心行为和响应处理的离线检查 |
| `Tests/ProviderChecks` | 使用临时模拟 CLI 与凭据样本的适配器离线检查 |
| `Resources` 与 `scripts` | 应用元数据、原创图标生成、构建、测试和发布打包 |

额度适配器返回服务商读数，模型不据此推导账单日期。自定义条目采用手动管理；Codex 和 Claude 可主动切换为手动额度。手动条目跳过服务商读取，保留自己的记录时间。菜单栏与工作台共用模型，按订阅展示剩余额度、重置时间与读取状态。

缺失数据保持可选，手动字段保留明显标记，凭据不得进入日志或已保存记录，演示模式与真实账号保持隔离。不同币种的金额分别汇总。界面默认简体中文，可切换英文。

## 验证

```bash
bash scripts/test.sh
bash scripts/package.sh --universal
lipo -info dist/AgentMeter.app/Contents/MacOS/AgentMeter
codesign --verify --deep --strict dist/AgentMeter.app
```

CI 在 macOS 14 和 15 上运行核心检查并生成通用应用。离线检查或 CI 构建成功不等于真实订阅账号已经验证。实机验证需要账号所有者已有的官方客户端登录状态，仅记录脱敏后的状态和额度。不要将凭据、本地偏好设置导出或原始账号响应提交为测试样本。

发布前检查工作台和菜单栏的两种界面语言与演示模式，再检查手动额度窗口与记录时间、自动条目切换手动、额度不可用或过期、服务商登录失败，以及手动更新操作。菜单栏必须区分缺失值、旧读数和手动记录。README 截图必须来自真实应用界面，并明确标记示例数据。

可通过 `swift run AgentMeter --render-screenshots docs/images` 生成两种语言的原生界面演示截图，菜单栏面板对应 `menu.png` 与 `menu-zh.png`。可选的 `swift run AgentMeter --probe codex` 或 `--probe claude` 会使用对应的真实本地登录状态进行只读额度检查；离线测试脚本与 CI 均不包含这一步。

## 打包与发布

```bash
bash scripts/package.sh --universal
```

脚本分别构建 `arm64-apple-macosx14.0` 和 `x86_64-apple-macosx14.0`，使用 `lipo` 合并可执行文件，生成：

```text
dist/AgentMeter.app
dist/AgentMeter-1.0.1-universal.zip
dist/AgentMeter-1.0.1-universal.zip.sha256
```

版本号来自 `Resources/Info.plist`。将 ZIP 和校验文件下载到同一目录，在该目录执行：

```bash
shasum -a 256 -c AgentMeter-1.0.1-universal.zip.sha256
```

校验和用于检查文件是否与发布文件一致，不代表 Developer ID 身份认证。默认使用临时签名（ad-hoc）；本地可通过 `CODESIGN_IDENTITY` 选择已有签名身份，但公证属于独立流程，脚本不会执行。构建过程不会修改 Gatekeeper 设置。

**Publish Release** 工作流支持推送 `v<版本号>` tag，或手动输入不含 `v` 的 `version`。版本必须与 `CFBundleShortVersionString` 一致。手动执行时，如果 tag 不存在，GitHub Release 会在所选工作流提交上创建该 tag；已有 tag 必须指向同一提交。已发布 Release 保持原样，工作流不会覆盖其附件。

发布新版本时，更新 `CFBundleShortVersionString` 并递增 `CFBundleVersion`，审查并提交变更，再推送匹配的 tag 或执行发布工作流。工作流重新运行检查，生成通用 ZIP 与校验文件，并将工作流 `GITHUB_TOKEN` 作为 `GH_TOKEN` 提供给发布命令；需要仓库 `contents: write` 权限。

## 更新行为

设置中的更新操作查询 `api.github.com/repos/NginxL/AgentMeter/releases/latest`，将三段式 Release 版本与当前应用版本比较。发现新版本后，在浏览器中打开本仓库发布页。应用不下载附件或替换自身；手动替换应用包会保留 `io.github.nginxl.AgentMeter` 中的偏好设置。

## 贡献

优先提交范围小、附相关验证的改动。行为变化时同步更新中英文说明。文档以真实字段和数据来源为依据，并区分离线样本覆盖与真实服务商兼容性。
