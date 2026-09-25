# 隐私与数据来源

[English](PRIVACY.md) · [README](../README.zh-CN.md)

AgentMeter 将订阅记录保存在你的 Mac 上，没有项目后端、分析 SDK、广告 SDK 或凭据导出功能。支持的额度适配器访问对应服务商；手动更新检查访问 GitHub。

## 凭据与网络访问

| 操作 | 来源与目标 | 边界 |
| --- | --- | --- |
| Codex 额度 | 启动本地 `codex app-server`，调用设置 `refreshToken: false` 的 `account/read` 以及 `account/rateLimits/read` | AgentMeter 不读取或修改 Codex 认证文件。官方 CLI 自行管理登录、凭据存储、令牌生命周期和服务商网络访问。 |
| Claude 额度 | 从 `~/.claude/.credentials.json` 或 `$CLAUDE_CONFIG_DIR/.credentials.json` 读取 `claudeAiOauth.accessToken`；默认配置可回退到 `Claude Code-credentials` 钥匙串服务 | 在内存中使用已有令牌，向 `https://api.anthropic.com/api/oauth/usage` 发送 GET 请求。AgentMeter 不刷新令牌或写入凭据；自定义配置目录不会回退到其他配置的默认钥匙串条目。 |
| 手动管理 | 用户填写的订阅与额度字段，包括自定义订阅及 Codex、Claude 的手动回退 | 不读取手动条目的凭据，也不发送额度请求。 |
| 更新检查 | GET `https://api.github.com/repos/NginxL/AgentMeter/releases/latest` | 仅手动触发，不附带服务商凭据或订阅记录。发现新版本后，在浏览器中打开 GitHub 发布页。 |
| 打开官方面板 | 在浏览器中打开 `chatgpt.com/codex/settings/usage` 或 `claude.ai/settings/usage` | 浏览器管理自身登录、Cookie 和网络行为；AgentMeter 不读取浏览器会话。 |

Claude 的 HTTP 会话禁用磁盘缓存与 Cookie，并拒绝重定向，避免将凭据转发到其他接口。

后台读取 Claude 凭据时禁止弹出钥匙串交互。只有明确的 Claude 连接操作才允许正常的 macOS 授权提示；取消或拒绝授权时，无法获取新读数，已有缓存可能继续显示并标记为过期。AgentMeter 不发起登录、不读取浏览器 Cookie、不创建 AI 对话，也不发送模型生成请求。

官方 Codex CLI 是独立程序，其网络、认证和遥测行为由该程序自身设置控制，AgentMeter 不覆盖这些设置。服务商接口和本地凭据格式可能变化，适配器可能因此需要更新。

## 本地存储

打包应用使用 `io.github.nginxl.AgentMeter` UserDefaults 域，包含以下内容：

| Key | 内容 |
| --- | --- |
| `subscriptions` | 名称、服务商类型、套餐名称、手动续费或到期日期、月度金额、币种、备注、启用状态、手动管理选项，以及附记录时间的手动额度窗口 |
| `snapshots` | 额度读数、来源、可用的套餐信息与获取时间；保存前移除账号标识 |
| `language` | 界面语言；默认简体中文，可切换英文 |
| `autoRefresh` | 是否启用每 15 分钟刷新的定时器 |

这些偏好设置属于本地应用数据，并非加密凭据保险库。请勿在备注中填写密码或令牌。AgentMeter 不主动将访问令牌、原始认证响应或凭据内容写入设置或日志。

演示数据仅保存在内存中，不会覆盖已保存的订阅记录或额度缓存。演示模式不调用额度适配器。

## 刷新与数据含义

自动刷新默认对使用自动来源的已启用条目开启：打开主面板时触发一次刷新，应用运行时每 15 分钟继续刷新，可以关闭。普通手动刷新操作与定时器共用同一限制：每个服务商至少间隔一分钟。明确的 Claude 授权操作允许立即重试。手动管理条目不参与这些读取。

重新启动后，已保存的自动额度会标记为过期，直到刷新成功并核对当前本地登录状态。自动读数超过 30 分钟或刷新失败也会标记为过期。登录缺失或凭据过期时，清除对应额度缓存。

手动额度读数附带记录时间与手动来源标记。保存额度变更时更新时间；只修改订阅备注或价格不会把额度标记为刚刚记录。手动读数不使用自动数据的新鲜度定时策略，不获取新数据，也不会自行重置。可记录最多两个窗口的已用百分比与可选重置时间。将自动条目切换为手动管理后，会清除其自动额度缓存，并停止该条目后续的自动读取。

菜单栏与工作台读取同一份本地模型；打开菜单不会创建单独的凭据存储或上传额度数据。自动额度的重置时间描述服务商额度窗口，手动额度的重置时间由用户填写。v1 中所有订阅续费或到期日期都由用户手动填写，月度金额也相同。AgentMeter 不访问发票、付款方式或账单门户。

## 删除本地数据

可在应用中删除单条订阅。要清除 AgentMeter 的全部偏好设置与额度缓存，请退出应用后执行：

```bash
defaults delete io.github.nginxl.AgentMeter
```

此命令清除 AgentMeter 的已保存记录和设置，不会退出 Codex 或 Claude Code 登录，也不会删除它们的凭据。退出登录与删除凭据由对应官方客户端管理。

反馈问题时，只提供相关错误状态和复现步骤。附件中的账号标识、邮箱、私人备注和凭据应先删除或遮盖。
