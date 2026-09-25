import SwiftUI
import AppKit
import MeterCore

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                AppMark(size: 31)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AgentMeter").font(.system(size: 14, weight: .bold))
                    Text(model.text("此刻，还有多少可用？", "A quick look at what’s left."))
                        .font(.system(size: 9)).foregroundStyle(MeterStyle.secondary)
                }
                Spacer()
                Button { Task { await model.refreshAll() } } label: {
                    if model.refreshing.isEmpty {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12)).padding(7)
                    } else { ProgressView().controlSize(.small).frame(width: 25, height: 25) }
                }
                .buttonStyle(.plain).foregroundStyle(MeterStyle.secondary)
                .disabled(!model.refreshing.isEmpty || model.demoMode || !model.subscriptions.contains(where: { $0.enabled && !$0.usesManualUsage }))
                .help(model.text("刷新额度", "Refresh usage"))
            }
            if model.demoMode {
                Label(model.text("演示数据 · 非个人账号数据", "Sample data · Not your account"), systemImage: "sparkles")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(MeterStyle.amber)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MeterStyle.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }
            ScrollView {
                VStack(spacing: 12) {
                    let subscriptions = model.subscriptions.filter { $0.enabled && ($0.provider != .manual || $0.manualUsage != nil) }
                    if subscriptions.isEmpty {
                        Text(model.text("在工作台添加工具，自动读取或手动记录额度。", "Add tools in the dashboard for automatic or manual usage tracking."))
                            .font(.system(size: 12)).foregroundStyle(MeterStyle.secondary).padding(15)
                    }
                    ForEach(subscriptions) { item in compactCard(item) }
                    if let next = nextBilling {
                        HStack(spacing: 9) {
                            Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(MeterStyle.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName(next) + " · " + (next.renewalKind == .renews ? model.text("订阅续费", "Subscription renewal") : model.text("订阅到期", "Subscription expiry")))
                                    .font(.system(size: 10, weight: .medium))
                                Text(meterDate(next.renewalDate!, language: model.language))
                                    .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
                            }
                            Spacer()
                            Text(meterCost(next.monthlyCost, currency: next.currency))
                                .font(.system(size: 12, weight: .semibold))
                        }.padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 445)
            HStack(spacing: 8) {
                Button { showDashboard("overview") } label: {
                    HStack {
                        Text(model.text("打开工作台", "Open dashboard"))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                }.buttonStyle(MeterButtonStyle(prominent: true))
                Button { showDashboard("settings") } label: {
                    Image(systemName: "gearshape").frame(width: 13, height: 13)
                }.buttonStyle(MeterButtonStyle()).help(model.text("设置", "Settings"))
            }
            HStack {
                Text(model.text("额度重置 ≠ 订阅续费", "Usage resets ≠ Subscription renewals"))
                Spacer()
                Button(model.text("退出", "Quit")) { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
            }.font(.system(size: 9)).foregroundStyle(MeterStyle.secondary)
        }
        .padding(18)
        .frame(width: 360)
        .background(MeterStyle.background)
        .foregroundStyle(MeterStyle.ink)
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: model.language == "zh" ? "zh_CN" : "en_US"))
    }

    private var nextBilling: Subscription? {
        model.subscriptions.filter { $0.enabled && ($0.renewalDate ?? .distantPast) >= Calendar.current.startOfDay(for: Date()) }
            .min { ($0.renewalDate ?? .distantFuture) < ($1.renewalDate ?? .distantFuture) }
    }

    private func compactCard(_ item: Subscription) -> some View {
        MeterCard(padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ProviderMark(provider: item.provider, size: 27)
                    Text(model.displayName(item)).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    let savedPlan = model.snapshot(for: item)?.plan ?? item.plan
                    if !savedPlan.isEmpty { MeterPill(text: planTitle(savedPlan, model: model), color: MeterStyle.providerColor(item.provider)) }
                }
                if let snapshot = model.snapshot(for: item), !snapshot.windows.isEmpty {
                    ForEach(snapshot.windows) { window in
                        QuotaWindowView(model: model, window: window, color: MeterStyle.providerColor(item.provider), compact: true)
                    }
                    if item.usesManualUsage {
                        Label(model.text("手动记录 · ", "Manual · ") + meterDate(snapshot.fetchedAt, language: model.language, includeTime: true), systemImage: "pencil.line")
                            .font(.system(size: 9)).foregroundStyle(MeterStyle.secondary)
                    } else if model.stale(snapshot: snapshot) {
                        Label(model.text("上次数据 · 等待刷新", "Last known data · Refresh needed"), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 9)).foregroundStyle(MeterStyle.amber)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.usesManualUsage ? model.text("尚未手动记录额度", "No manual usage recorded") : model.text("额度暂不可用", "Usage unavailable"))
                            .font(.system(size: 12, weight: .medium))
                        Text(item.usesManualUsage
                             ? model.text("在工作台录入官方页面显示的已用比例与重置时间。", "Record the used percentage and reset time from the provider in the dashboard.")
                             : model.errors[item.id] ?? model.text("先在官方客户端登录，然后刷新。", "Sign in through the official client, then refresh."))
                            .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(item.usesManualUsage ? model.text("管理额度记录", "Manage usage record") : model.text("打开连接设置", "Open connection settings")) {
                            showDashboard(item.usesManualUsage ? "subscriptions" : "settings")
                        }
                            .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(MeterStyle.accent)
                    }
                }
            }
        }
    }

    private func showDashboard(_ tab: String) {
        model.selectedTab = tab
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
