import SwiftUI
import MeterCore

struct SettingsContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            MeterCard {
                VStack(alignment: .leading, spacing: 21) {
                    sectionTitle(model.text("通用", "General"), icon: "slider.horizontal.3")
                    HStack {
                        settingDescription(model.text("显示语言", "Display language"), detail: model.text("即刻切换界面语言。", "Applies immediately throughout the app."))
                        Spacer()
                        Picker(model.text("显示语言", "Display language"), selection: $model.language) {
                            Text("简体中文").tag("zh")
                            Text("English").tag("en")
                        }.labelsHidden().frame(width: 140)
                    }
                    Divider()
                    Toggle(isOn: $model.autoRefresh) {
                        settingDescription(model.text("自动刷新额度", "Refresh usage automatically"), detail: model.text("每 \(Int(MeterPolicy.refreshInterval / 60)) 分钟读取一次已启用的自动额度；手动记录不变。", "Refreshes automatic usage every \(Int(MeterPolicy.refreshInterval / 60)) minutes. Manual records stay unchanged."))
                    }.toggleStyle(.switch).controlSize(.small)
                    Divider()
                    Toggle(isOn: Binding(get: { model.demoMode }, set: { model.setDemoMode($0) })) {
                        settingDescription(model.text("演示模式", "Demo mode"), detail: model.text("使用独立的示例数据预览界面，不改动真实订阅记录。", "Preview with separate sample data. Your real subscription records stay saved."))
                    }.toggleStyle(.switch).controlSize(.small)
                }
            }
            MeterCard {
                VStack(alignment: .leading, spacing: 20) {
                    sectionTitle(model.text("账号连接", "Account connections"), icon: "link")
                    ForEach(Array(ProviderKind.selectableCases.filter(\.supportsAutomaticUsage).enumerated()), id: \.element) { index, provider in
                        if index > 0 { Divider() }
                        connectionRow(provider)
                    }
                    Text(model.text("支持自动读取的服务每家使用一个本机登录。所有工具均可手动记录额度，记录时间与自动刷新时间分别显示。", "Automatic providers use one local login each. Every tool supports manual usage records with their own recording time."))
                        .font(.system(size: 11)).foregroundStyle(MeterStyle.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            MeterCard {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle(model.text("关于 AgentMeter", "About AgentMeter"), icon: "info.circle")
                    HStack(alignment: .center, spacing: 14) {
                        AppMark(size: 45)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("AgentMeter " + version).font(.system(size: 14, weight: .semibold))
                            Text(model.text("让 AI 订阅与额度更清晰。", "A clearer view of your AI plans and limits."))
                                .font(.system(size: 11)).foregroundStyle(MeterStyle.secondary)
                        }
                        Spacer()
                        Button { Task { await model.checkForUpdates() } } label: {
                            HStack(spacing: 6) {
                                if model.checkingUpdate { ProgressView().controlSize(.mini) }
                                Text(model.checkingUpdate ? model.text("正在检查…", "Checking…") : model.text("检查更新", "Check for updates"))
                            }
                        }.buttonStyle(MeterButtonStyle()).disabled(model.checkingUpdate)
                    }
                    if let message = model.updateMessage {
                        Text(message).font(.system(size: 11)).foregroundStyle(MeterStyle.secondary).textSelection(.enabled)
                    }
                    Divider()
                    HStack(spacing: 18) {
                        Link(destination: URL(string: "https://github.com/NginxL/AgentMeter")!) {
                            Label(model.text("项目主页", "GitHub project"), systemImage: "arrow.up.right.square")
                        }
                        Link(destination: URL(string: "https://github.com/NginxL/AgentMeter/releases")!) {
                            Label(model.text("下载与版本记录", "Downloads & releases"), systemImage: "arrow.down.circle")
                        }
                    }.font(.system(size: 11)).foregroundStyle(MeterStyle.accent)
                }
            }
        }
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1" }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
    }

    private func settingDescription(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(MeterStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectionRow(_ provider: ProviderKind) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderMark(provider: provider, size: 35)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.displayName(Subscription(provider: provider, name: provider.name)))
                    .font(.system(size: 12, weight: .semibold))
                Text(connectionDescription(provider))
                    .font(.system(size: 11)).foregroundStyle(MeterStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if provider == .claude {
                Button { Task { await model.authorizeClaude() } } label: {
                    Text(model.text("授权读取 Claude", "Connect Claude"))
                }
                .buttonStyle(MeterButtonStyle())
                .disabled(model.demoMode || !model.subscriptions.contains(where: { $0.provider == .claude && $0.enabled && !$0.usesManualUsage }))
                .help(model.text("需要启用 Claude 订阅。允许读取本机已有登录，不会更改服务商凭据。", "Requires an enabled Claude subscription. Reads your existing local login without changing provider credentials."))
            } else {
                Button { model.openDashboard(provider) } label: {
                        Label(model.text("官方用量", "Usage page"), systemImage: "arrow.up.right")
                }.buttonStyle(MeterButtonStyle())
            }
        }
    }

    private func connectionDescription(_ provider: ProviderKind) -> String {
        switch provider {
        case .codex:
            return model.text("使用 Codex CLI 的现有订阅登录读取额度。", "Reads usage through your existing Codex CLI subscription login.")
        case .claude:
            return model.text("连接时允许读取 Claude 的本机登录凭据。", "Connect to allow access to Claude’s existing local login.")
        default:
            return model.text("手动记录订阅和额度。", "Manually tracked plan and usage.")
        }
    }
}
