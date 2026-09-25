import SwiftUI
import MeterCore

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var editing: Subscription?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(MeterStyle.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.demoMode { demoBanner }
                    header
                    if model.selectedTab == "settings" {
                        SettingsContent(model: model)
                    } else if model.selectedTab == "subscriptions" {
                        summary
                        SubscriptionList(model: model, editing: $editing)
                    } else {
                        summary
                        quotaSection
                        Button { model.selectedTab = "subscriptions" } label: {
                            Label(model.text("管理全部订阅与账期", "Manage all plans & billing"), systemImage: "arrow.right")
                        }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(MeterStyle.accent)
                    }
                    footer
                }
                .padding(28)
            }
        }
        .background(MeterStyle.background)
        .foregroundStyle(MeterStyle.ink)
        .tint(MeterStyle.accent)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: model.language == "zh" ? "zh_CN" : "en_US"))
        .frame(minWidth: 900, minHeight: 660)
        .sheet(item: $editing) { subscription in
            SubscriptionEditorView(model: model, subscription: subscription)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppMark()
                VStack(alignment: .leading, spacing: 3) {
                    Text("AgentMeter").font(.system(size: 17, weight: .bold))
                    Text(model.text("AI 订阅与额度", "AI plans & limits"))
                        .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
                }
            }
            .padding(.bottom, 39)
            Text(model.text("工作空间", "WORKSPACE"))
                .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                .foregroundStyle(MeterStyle.secondary)
                .padding(.leading, 12).padding(.bottom, 12)
            navButton("overview", icon: "square.grid.2x2", title: model.text("总览", "Overview"))
            navButton("subscriptions", icon: "creditcard", title: model.text("订阅管理", "Subscriptions"))
            navButton("settings", icon: "slider.horizontal.3", title: model.text("设置", "Settings"))
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(model.demoMode ? MeterStyle.amber : MeterStyle.accent).frame(width: 6, height: 6)
                    Text(model.demoMode ? model.text("演示数据", "Sample data") : model.text("本机工作空间", "Local workspace"))
                        .font(.system(size: 11, weight: .medium))
                }
                Text(model.text("让每一份订阅都心中有数。", "A little clarity for every plan."))
                    .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    languageButton("zh", title: "中文")
                    languageButton("en", title: "EN")
                    Spacer()
                    Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"))
                        .font(.system(size: 9)).foregroundStyle(MeterStyle.secondary)
                }
                .padding(.top, 8)
            }
            .padding(12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(width: 208)
        .background(Color.white.opacity(0.62))
    }

    private func navButton(_ value: String, icon: String, title: String) -> some View {
        Button { model.selectedTab = value } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 20)
                Text(title)
                    .font(.system(size: 12, weight: model.selectedTab == value ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.95)
                    .layoutPriority(1)
                Spacer()
                if model.selectedTab == value { Circle().fill(MeterStyle.accent).frame(width: 5, height: 5) }
            }
            .foregroundStyle(model.selectedTab == value ? MeterStyle.accent : MeterStyle.secondary)
            .padding(.horizontal, 12).padding(.vertical, 13)
            .background(model.selectedTab == value ? MeterStyle.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 5)
    }

    private func languageButton(_ value: String, title: String) -> some View {
        Button { model.language = value } label: {
            Text(title).font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .foregroundStyle(model.language == value ? MeterStyle.ink : MeterStyle.secondary)
                .background(model.language == value ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }

    private var demoBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles").font(.system(size: 12))
            Text(model.text("演示模式 · 以下为示例数据，不代表你的账号", "Demo mode · Sample data, not your account"))
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 8)
            Button(model.text("退出演示", "Exit demo")) { model.setDemoMode(false) }
                .font(.system(size: 11, weight: .semibold)).buttonStyle(.plain)
        }
        .foregroundStyle(MeterStyle.amber)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(MeterStyle.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(headerEyebrow).font(.system(size: 9, weight: .semibold)).tracking(1.6).foregroundStyle(MeterStyle.secondary)
                Text(headerTitle).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(headerSubtitle).font(.system(size: 12)).foregroundStyle(MeterStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if model.selectedTab != "settings" {
                Button { Task { await model.refreshAll() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 13, height: 13)
                }
                .buttonStyle(MeterButtonStyle())
                .disabled(!model.refreshing.isEmpty || model.demoMode || !model.subscriptions.contains(where: { $0.enabled && !$0.usesManualUsage }))
                .help(model.text("刷新额度", "Refresh usage"))
                Button { editing = Subscription(provider: .manual, name: "") } label: {
                    Label(model.text("添加订阅", "Add plan"), systemImage: "plus")
                }.buttonStyle(MeterButtonStyle(prominent: true))
            }
        }
    }

    private var headerEyebrow: String {
        switch model.selectedTab {
        case "settings": return model.text("偏好设置", "PREFERENCES")
        case "subscriptions": return model.text("订阅账本", "YOUR SUBSCRIPTIONS")
        default: return model.text("工作空间总览", "WORKSPACE OVERVIEW")
        }
    }

    private var headerTitle: String {
        switch model.selectedTab {
        case "settings": return model.text("按你的习惯来", "Make it yours")
        case "subscriptions": return model.text("订阅，一目了然", "Every plan, in one place")
        default: return model.text("你的 AI 工作台", "Your AI, at a glance")
        }
    }

    private var headerSubtitle: String {
        switch model.selectedTab {
        case "settings": return model.text("管理语言、刷新频率与应用更新。", "Language, refresh preferences, and app updates.")
        case "subscriptions": return model.text("记录套餐与续费日期，提前安排下一笔支出。", "Keep track of plans, billing dates, and what comes next.")
        default: return model.text("掌握可用额度，也记得下一次续费。", "A clear view of your limits and your next renewal.")
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            SummaryTile(icon: "square.stack.3d.up", title: model.text("正在管理", "TRACKED PLANS"), value: "\(model.subscriptions.filter(\.enabled).count)", detail: model.text("份启用的订阅", "enabled subscriptions"))
            SummaryTile(icon: "creditcard", title: model.text("已记录月费", "RECORDED MONTHLY"), value: monthlyTotal, detail: model.text("仅统计手动填写的费用", "from your saved amounts"))
            SummaryTile(icon: "calendar", title: model.text("下一账期", "NEXT BILLING DATE"), value: nextRenewalValue, detail: nextRenewalDetail)
        }
    }

    private var monthlyTotal: String {
        let subscriptions = model.subscriptions.filter { $0.enabled && $0.monthlyCost != nil }
        let groups = Dictionary(grouping: subscriptions, by: \.currency)
        if groups.isEmpty { return "—" }
        if groups.count > 1 { return model.text("多币种", "Mixed currencies") }
        guard let entry = groups.first else { return "—" }
        return meterCost(entry.value.reduce(0) { $0 + ($1.monthlyCost ?? 0) }, currency: entry.key)
    }

    private var nextSubscription: Subscription? {
        model.subscriptions.filter { $0.enabled && ($0.renewalDate ?? .distantPast) >= Calendar.current.startOfDay(for: Date()) }
            .min { ($0.renewalDate ?? .distantFuture) < ($1.renewalDate ?? .distantFuture) }
    }

    private var nextRenewalValue: String {
        guard let date = nextSubscription?.renewalDate else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: model.language == "zh" ? "zh_CN" : "en_US")
        formatter.dateFormat = model.language == "zh" ? "M月d日" : "MMM d"
        return formatter.string(from: date)
    }

    private var nextRenewalDetail: String {
        guard let item = nextSubscription else {
            if model.subscriptions.contains(where: { $0.enabled && $0.renewalDate != nil }) {
                return model.text("账期已过，请更新记录", "past billing dates need updating")
            }
            return model.text("添加续费或到期日期", "add a renewal or expiry date")
        }
        let action = item.renewalKind == .renews ? model.text("续费", "renews") : model.text("到期", "expires")
        return "\(model.displayName(item)) · \(action)"
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.text("用量概览", "Usage overview")).font(.system(size: 16, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(MeterStyle.accent).frame(width: 5, height: 5)
                    Text(model.text("自动读取与手动记录", "Automatic & manually recorded"))
                        .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
                }
            }
            let tracked = model.subscriptions.filter { $0.enabled && ($0.provider != .manual || $0.manualUsage != nil) }
            if tracked.isEmpty {
                MeterCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.text("添加工具，集中管理额度", "Add a tool to track usage"), systemImage: "chart.bar")
                            .font(.system(size: 14, weight: .medium))
                        Text(model.text("支持的服务可自动读取，其他工具可手动记录已用比例与重置时间。", "Supported services can refresh automatically. Record usage and reset dates manually for other tools."))
                            .font(.system(size: 12)).foregroundStyle(MeterStyle.secondary)
                        Button(model.text("添加自动读取的订阅", "Add a connected plan")) { editing = Subscription(provider: .codex, name: "Codex") }
                            .buttonStyle(MeterButtonStyle())
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(tracked) { subscription in
                        QuotaCard(model: model, subscription: subscription) { editing = subscription }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
            Text(model.text("额度重置与订阅续费是两条独立时间线。", "Usage resets and subscription renewals follow separate schedules."))
            Spacer()
            if let date = model.lastRefresh {
                Text(model.text("上次刷新 ", "Refreshed ") + date.formatted(date: .omitted, time: .shortened))
            }
        }
        .font(.system(size: 9)).foregroundStyle(MeterStyle.secondary)
    }
}

private struct SummaryTile: View {
    var icon: String
    var title: String
    var value: String
    var detail: String
    var body: some View {
        MeterCard(padding: 17) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 11))
                    Text(title).font(.system(size: 9, weight: .medium)).tracking(0.5)
                }.foregroundStyle(MeterStyle.secondary)
                Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).font(.system(size: 10)).foregroundStyle(MeterStyle.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

struct QuotaCard: View {
    @ObservedObject var model: AppModel
    var subscription: Subscription
    var edit: () -> Void
    private var snapshot: UsageSnapshot? { model.snapshot(for: subscription) }
    private var color: Color { MeterStyle.providerColor(subscription.provider) }

    var body: some View {
        MeterCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 11) {
                    ProviderMark(provider: subscription.provider)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.displayName(subscription)).font(.system(size: 17, weight: .semibold))
                        HStack(spacing: 5) {
                            MeterPill(text: plan, color: color)
                            if subscription.usesManualUsage { MeterPill(text: model.text("手动记录", "Manual")) }
                        }
                    }
                    Spacer()
                    Button(action: edit) { Image(systemName: "slider.horizontal.3").font(.system(size: 13)) }
                        .buttonStyle(.plain).foregroundStyle(MeterStyle.secondary)
                        .help(model.text("编辑订阅", "Edit subscription"))
                }
                if let snapshot, !snapshot.windows.isEmpty {
                    VStack(alignment: .leading, spacing: 19) {
                        ForEach(snapshot.windows) { window in
                            QuotaWindowView(model: model, window: window, color: color)
                        }
                    }
                    if !subscription.usesManualUsage && (model.stale(snapshot: snapshot) || model.errors[subscription.id] != nil) {
                        Label(model.text("显示上次数据 · 刷新后查看最新额度", "Last known data · Refresh for current limits"), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10)).foregroundStyle(MeterStyle.amber)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(model.errors[subscription.id] ?? "")
                    }
                } else {
                    emptyState
                }
                Divider().overlay(MeterStyle.line)
                HStack(spacing: 7) {
                    if subscription.usesManualUsage {
                        Image(systemName: "pencil.line")
                        if let snapshot {
                            Text(model.text("记录于 ", "Recorded ") + meterDate(snapshot.fetchedAt, language: model.language, includeTime: true))
                        } else { Text(model.text("尚未记录额度", "No usage recorded")) }
                    } else if model.refreshing.contains(subscription.id) {
                        ProgressView().controlSize(.mini)
                        Text(model.text("正在读取…", "Reading…"))
                    } else if let snapshot {
                        Image(systemName: model.demoMode ? "sparkles" : "arrow.triangle.2.circlepath")
                        Text(model.demoMode ? model.text("示例额度", "Sample usage") : model.text("更新于 ", "Updated ") + snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
                    } else {
                        Image(systemName: "link")
                        Text(model.text("等待首次读取", "Awaiting first sync"))
                    }
                    Spacer()
                    if subscription.provider != .manual {
                        Button { model.openDashboard(subscription.provider) } label: {
                            Image(systemName: "arrow.up.right.square").font(.system(size: 12))
                        }.buttonStyle(.plain).help(model.text("打开官方用量入口", "Open official usage"))
                    }
                    if subscription.usesManualUsage {
                        Button(action: edit) { Image(systemName: "square.and.pencil").font(.system(size: 12)) }
                            .buttonStyle(.plain).help(model.text("更新额度记录", "Update usage record"))
                    } else {
                        Button { Task { await model.refresh(id: subscription.id) } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 12))
                        }.buttonStyle(.plain).disabled(model.refreshing.contains(subscription.id) || model.demoMode).help(model.text("刷新额度", "Refresh usage"))
                    }
                }
                .font(.system(size: 9)).foregroundStyle(MeterStyle.secondary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var plan: String {
        if let plan = snapshot?.plan, !plan.isEmpty { return planTitle(plan, model: model) }
        return subscription.plan.isEmpty ? model.text("套餐未识别", "Plan not available") : planTitle(subscription.plan, model: model)
    }

    private var emptyState: some View {
        Group {
            if subscription.usesManualUsage { manualEmptyState }
            else { automaticEmptyState }
        }
    }

    private var manualEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.text("从官方页面记录额度", "Record usage from the provider"), systemImage: "pencil.line")
                .font(.system(size: 13, weight: .semibold))
            Text(model.text("手动额度不会自动更新。记录已用比例及重置时间，便于与其他工具一起查看。", "Manual records do not update automatically. Add the used percentage and reset time to see usage alongside your other tools."))
                .font(.system(size: 11)).foregroundStyle(MeterStyle.secondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.text("尚未记录", "Not recorded"))
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(MeterStyle.secondary.opacity(0.5)).padding(.vertical, 8)
            HStack(spacing: 8) {
                Button(action: edit) { Label(model.text("记录额度", "Record usage"), systemImage: "pencil") }
                    .buttonStyle(MeterButtonStyle())
                if subscription.provider != .manual {
                    Button { model.openDashboard(subscription.provider) } label: {
                        Image(systemName: "arrow.up.right.square")
                    }.buttonStyle(MeterButtonStyle()).help(model.text("打开官方客户端", "Open official client"))
                }
            }
        }.frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
    }

    private var automaticEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus").foregroundStyle(color)
                Text(model.text("连接后查看剩余额度", "Connect to see available usage"))
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(model.errors[subscription.id] ?? model.text("先在官方客户端登录订阅账号，然后刷新。额度读取成功后会显示在这里。", "Sign in to your subscription in the official client, then refresh. Your usage limits will appear here."))
                .font(.system(size: 11)).foregroundStyle(MeterStyle.secondary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Text(model.text("暂无额度数据", "Usage unavailable"))
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(MeterStyle.secondary.opacity(0.5))
                .padding(.vertical, 8)
            if subscription.provider == .claude {
                Button { Task { await model.authorizeClaude() } } label: {
                    Label(model.text("授权读取 Claude", "Connect Claude"), systemImage: "link")
                }
                .buttonStyle(MeterButtonStyle())
                .disabled(model.demoMode)
                .help(model.text("允许读取本机已有登录；不会更改服务商凭据。", "Allows reading your existing local login without changing provider credentials."))
            } else {
                Button { model.openDashboard(subscription.provider) } label: {
                    Label(model.text("打开官方用量页面", "Open official usage page"), systemImage: "arrow.up.right")
                }.buttonStyle(MeterButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
    }
}

struct QuotaWindowView: View {
    @ObservedObject var model: AppModel
    var window: QuotaWindow
    var color: Color
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(quotaTitle(window, model: model)).font(.system(size: compact ? 10 : 11, weight: .medium)).foregroundStyle(MeterStyle.secondary)
                Spacer()
                if let remaining = window.remainingPercent {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(remaining.rounded()))").font(.system(size: compact ? 18 : 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("%").font(.system(size: compact ? 10 : 13, weight: .medium))
                        Text(model.text("剩余", "left")).font(.system(size: 9)).foregroundStyle(MeterStyle.secondary).padding(.leading, 3)
                    }
                } else {
                    Text(model.text("暂无数据", "Unavailable")).font(.system(size: 11, weight: .medium)).foregroundStyle(MeterStyle.secondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(MeterStyle.background)
                    if let remaining = window.remainingPercent {
                        Capsule().fill(remaining <= 10 ? MeterStyle.amber : color)
                            .frame(width: max(0, geometry.size.width * remaining / 100))
                    }
                }
            }.frame(height: compact ? 5 : 7)
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 8))
                if let reset = window.resetsAt {
                    Text(model.text("重置于 ", "Resets ") + meterDate(reset, language: model.language, includeTime: true))
                } else {
                    Text(model.text("重置时间未提供", "Reset time unavailable"))
                }
            }.font(.system(size: compact ? 9 : 10)).foregroundStyle(MeterStyle.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SubscriptionList: View {
    @ObservedObject var model: AppModel
    @Binding var editing: Subscription?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.text("订阅与账期", "Plans & billing")).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(model.text("套餐信息与账期由你维护", "Plan details and billing dates are entered by you"))
                    .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
            }
            MeterCard(padding: 0) {
                VStack(spacing: 0) {
                    if model.subscriptions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.text("从第一份订阅开始", "Start with your first subscription")).font(.system(size: 14, weight: .medium))
                            Text(model.text("添加任意 AI 工具，记录套餐、月费与续费日期。", "Add any AI tool to track its plan, monthly cost, and renewal date."))
                                .font(.system(size: 12)).foregroundStyle(MeterStyle.secondary)
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(model.subscriptions.enumerated()), id: \.element.id) { index, subscription in
                            SubscriptionRow(model: model, subscription: subscription) { editing = subscription }
                            if index < model.subscriptions.count - 1 { Divider().padding(.horizontal, 19) }
                        }
                    }
                }
            }
        }
    }
}

private struct SubscriptionRow: View {
    @ObservedObject var model: AppModel
    var subscription: Subscription
    var edit: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ProviderMark(provider: subscription.provider, size: 33)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.displayName(subscription)).font(.system(size: 12, weight: .semibold))
                    if !subscription.enabled { MeterPill(text: model.text("已停用", "Disabled")) }
                }
                Text(subscription.plan.isEmpty ? model.text("套餐待填写", "Add plan details") : planTitle(subscription.plan, model: model))
                    .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            MeterPill(text: subscription.usesManualUsage ? model.text("手动记录额度", "Manual usage") : model.text("自动读取额度", "Automatic usage"), color: subscription.usesManualUsage ? MeterStyle.secondary : MeterStyle.accent)
            VStack(alignment: .trailing, spacing: 4) {
                Text(meterCost(subscription.monthlyCost, currency: subscription.currency) + (subscription.monthlyCost == nil ? "" : model.text(" / 月", " / mo")))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                if let date = subscription.renewalDate {
                    Text(billingLabel(date) + meterDate(date, language: model.language))
                        .font(.system(size: 9)).foregroundStyle(date < Calendar.current.startOfDay(for: Date()) ? MeterStyle.amber : MeterStyle.secondary)
                } else {
                    Text(model.text("账期未填写", "Billing date not set")).font(.system(size: 9)).foregroundStyle(MeterStyle.secondary)
                }
            }.frame(minWidth: 125, alignment: .trailing)
            Button(action: edit) { Image(systemName: "pencil").font(.system(size: 11)).padding(7) }
                .buttonStyle(.plain).foregroundStyle(MeterStyle.secondary).help(model.text("编辑订阅", "Edit subscription"))
        }.padding(.horizontal, 19).padding(.vertical, 15)
    }

    private func billingLabel(_ date: Date) -> String {
        if date < Calendar.current.startOfDay(for: Date()) {
            return subscription.renewalKind == .renews ? model.text("账期待更新 · ", "Update billing · ") : model.text("已到期 · ", "Expired · ")
        }
        return subscription.renewalKind == .renews ? model.text("续费 ", "Renews ") : model.text("到期 ", "Expires ")
    }
}
