import AppKit
import Combine
import Foundation
import MeterCore
import MeterProviders

typealias Subscription = MeterCore.Subscription

@MainActor
final class AppModel: ObservableObject {
    @Published var subscriptions: [Subscription] = []
    @Published var snapshots: [UUID: UsageSnapshot] = [:]
    @Published var errors: [UUID: String] = [:]
    @Published var refreshing: Set<UUID> = []
    @Published var demoMode = false
    @Published var selectedTab = "overview"
    @Published var language = "zh" { didSet { if !demoMode { defaults.set(language, forKey: "language") } } }
    @Published var autoRefresh = true { didSet { if !demoMode { defaults.set(autoRefresh, forKey: "autoRefresh") } } }
    @Published var lastRefresh: Date?
    @Published var updateMessage: String?
    @Published var checkingUpdate = false

    private let defaults: UserDefaults
    private var timer: AnyCancellable?
    private var generation = UUID()
    private var realSubscriptions: [Subscription] = []
    private var realSnapshots: [UUID: UsageSnapshot] = [:]
    private var realErrors: [UUID: String] = [:]
    private var realLanguage = "zh"
    private var realAutoRefresh = true
    private var validatedSnapshotIDs: Set<UUID> = []
    private var realValidatedSnapshotIDs: Set<UUID> = []
    private var providers: [ProviderKind: any UsageProvider]
    private var lastAttempt: [ProviderKind: Date] = [:]

    init(demo: Bool = false, defaults: UserDefaults = .standard,
         providers: [ProviderKind: any UsageProvider]? = nil, startTimer: Bool = true) {
        self.defaults = defaults
        self.providers = providers ?? [.codex: CodexProvider(), .claude: ClaudeProvider(), .trae: TraeProvider()]
        language = defaults.string(forKey: "language") ?? "zh"
        autoRefresh = defaults.object(forKey: "autoRefresh") as? Bool ?? true
        if let data = defaults.data(forKey: "subscriptions"),
           let stored = try? JSONDecoder().decode([Subscription].self, from: data) {
            subscriptions = stored
        } else { subscriptions = Subscription.defaults }
        if let data = defaults.data(forKey: "snapshots"),
           let stored = try? JSONDecoder().decode([UUID: UsageSnapshot].self, from: data) {
            let allowed = Set(subscriptions.map(\.id))
            snapshots = stored.filter { allowed.contains($0.key) }
        }
        if demo { setDemoMode(true) }
        if startTimer {
            timer = Timer.publish(every: MeterPolicy.refreshInterval, on: .main, in: .common)
                .autoconnect().sink { [weak self] _ in
                    guard let self, self.autoRefresh, !self.demoMode else { return }
                    Task { await self.refreshAll() }
                }
        }
    }

    func text(_ zh: String, _ en: String) -> String { language == "en" ? en : zh }

    func displayName(_ item: Subscription) -> String {
        if item.provider == .doubao && ["豆包工作", "Doubao Work"].contains(item.name) {
            return text("豆包工作", "Doubao Work")
        }
        return item.name
    }

    func snapshot(for item: Subscription) -> UsageSnapshot? {
        guard item.usesManualUsage else { return snapshots[item.id] }
        guard let usage = item.manualUsage, !usage.windows.isEmpty else { return nil }
        return UsageSnapshot(provider: item.provider, plan: item.plan.isEmpty ? nil : item.plan,
            windows: usage.windows, fetchedAt: usage.recordedAt, source: "Manual")
    }

    func stale(snapshot: UsageSnapshot) -> Bool {
        guard !demoMode, snapshot.source != "Manual" else { return false }
        // Disk cache has no verified association with the current local login.
        // Only a successful read in this session can make a real snapshot current.
        return MeterPolicy.isStale(snapshot) || !subscriptions.contains {
            snapshots[$0.id] == snapshot && validatedSnapshotIDs.contains($0.id) && errors[$0.id] == nil
        }
    }

    func refreshAll() async {
        guard !demoMode else { return }
        let ids = subscriptions.filter { $0.enabled && !$0.usesManualUsage }.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in ids { group.addTask { await self.refresh(id: id) } }
        }
    }

    func refresh(id: UUID) async {
        guard !demoMode, !refreshing.contains(id),
              let item = subscriptions.first(where: { $0.id == id && $0.enabled && !$0.usesManualUsage }),
              let provider = providers[item.provider] else { return }
        // Manual refresh is debounced too: repeated clicks must not hammer a quota endpoint.
        if let attempt = lastAttempt[item.provider], Date().timeIntervalSince(attempt) < 60 { return }
        lastAttempt[item.provider] = Date()
        let requestGeneration = generation
        refreshing.insert(id)
        defer { if generation == requestGeneration { refreshing.remove(id) } }
        do {
            let snapshot = try await provider.fetch()
            guard generation == requestGeneration, !demoMode,
                  subscriptions.contains(where: { $0.id == id && $0.enabled && !$0.usesManualUsage }) else { return }
            snapshots[id] = snapshot
            validatedSnapshotIDs.insert(id)
            errors[id] = nil
            lastRefresh = snapshot.fetchedAt
            persist()
        } catch {
            guard generation == requestGeneration, !demoMode,
                  subscriptions.contains(where: { $0.id == id && $0.enabled && !$0.usesManualUsage }) else { return }
            if let failure = error as? MeterFailure {
                switch failure {
                case .notSignedIn, .expired, .unsupportedAccount:
                    snapshots[id] = nil
                    validatedSnapshotIDs.remove(id)
                default: break
                }
                errors[id] = message(for: failure)
            } else {
                errors[id] = text("读取失败，请检查网络或重新登录官方客户端。", "Unable to refresh. Check your connection or sign in through the official client.")
            }
            persist()
        }
    }

    func save(_ subscription: Subscription) {
        var valid = subscription
        valid.name = valid.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valid.name.isEmpty else { return }
        if let amount = valid.monthlyCost, !amount.isFinite || amount < 0 { valid.monthlyCost = nil }
        if let index = subscriptions.firstIndex(where: { $0.id == valid.id }) {
            // An adapter follows one official local login; additional accounts must be manual entries.
            valid.provider = subscriptions[index].provider
            subscriptions[index] = valid
        } else {
            if valid.provider != .manual && subscriptions.contains(where: { $0.provider == valid.provider }) {
                valid.provider = .manual
            }
            subscriptions.append(valid)
        }
        if !valid.enabled || valid.usesManualUsage {
            snapshots[valid.id] = nil
            errors[valid.id] = nil
            validatedSnapshotIDs.remove(valid.id)
        }
        persist()
    }

    func delete(id: UUID) {
        subscriptions.removeAll { $0.id == id }
        snapshots[id] = nil
        errors[id] = nil
        validatedSnapshotIDs.remove(id)
        persist()
    }

    func setDemoMode(_ value: Bool) {
        guard value != demoMode else { return }
        generation = UUID()
        refreshing.removeAll()
        if value {
            realSubscriptions = subscriptions; realSnapshots = snapshots; realErrors = errors
            realLanguage = language; realAutoRefresh = autoRefresh
            realValidatedSnapshotIDs = validatedSnapshotIDs
            validatedSnapshotIDs = []
            demoMode = true
            let now = Date()
            let codex = Subscription(provider: .codex, name: "Codex", plan: "Plus", renewalDate: now.addingTimeInterval(9 * 86400), monthlyCost: 20)
            let claude = Subscription(provider: .claude, name: "Claude", plan: "Pro", renewalDate: now.addingTimeInterval(4 * 86400), monthlyCost: 20)
            let cursor = Subscription(provider: .manual, name: "Cursor", plan: "Pro", renewalDate: now.addingTimeInterval(18 * 86400), monthlyCost: 20, notes: "手动登记的订阅示例 · Manually tracked example")
            let trae = Subscription(provider: .trae, name: "TRAE SOLO CN", plan: "Example", currency: "CNY")
            let doubao = Subscription(provider: .doubao, name: "豆包工作", plan: "Example", currency: "CNY", manualUsage: ManualUsage(windows: [
                QuotaWindow(id: "manual.current", title: "Current period", usedPercent: 24, resetsAt: now.addingTimeInterval(2 * 3600)),
                QuotaWindow(id: "manual.weekly", title: "Weekly", usedPercent: 38, resetsAt: now.addingTimeInterval(4 * 86400))
            ], recordedAt: now))
            subscriptions = [codex, claude, trae, doubao, cursor]
            snapshots = [
                trae.id: UsageSnapshot(provider: .trae, plan: "Example", windows: [QuotaWindow(id: "trae.credits", title: "Credits", usedPercent: 27)], source: "Demo / 演示数据"),
                codex.id: UsageSnapshot(provider: .codex, plan: "Plus", windows: [
                    QuotaWindow(id: "codex.primary", title: "5 hours", usedPercent: 32, resetsAt: now.addingTimeInterval(2 * 3600 + 24 * 60)),
                    QuotaWindow(id: "codex.secondary", title: "Weekly", usedPercent: 57, resetsAt: now.addingTimeInterval(3 * 86400))
                ], source: "Demo / 演示数据"),
                claude.id: UsageSnapshot(provider: .claude, plan: "Pro", windows: [
                    QuotaWindow(id: "five_hour", title: "5 hours", usedPercent: 18, resetsAt: now.addingTimeInterval(3 * 3600 + 46 * 60)),
                    QuotaWindow(id: "seven_day", title: "Weekly", usedPercent: 44, resetsAt: now.addingTimeInterval(5 * 86400))
                ], source: "Demo / 演示数据")
            ]
            errors = [:]
        } else {
            // Restore preferences before leaving demo so its edits are never persisted.
            language = realLanguage; autoRefresh = realAutoRefresh
            demoMode = false
            subscriptions = realSubscriptions; snapshots = realSnapshots; errors = realErrors
            validatedSnapshotIDs = realValidatedSnapshotIDs
            lastAttempt = [:]
        }
    }

    func openDashboard(_ provider: ProviderKind) {
        let address: String
        switch provider {
        case .codex: address = "https://chatgpt.com/codex/settings/usage"
        case .claude: address = "https://claude.ai/settings/usage"
        case .trae, .doubao:
            let bundle = provider == .trae ? "cn.trae.solo.app" : "com.work.pc.doubao"
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                return
            }
            address = provider == .trae ? "https://www.trae.cn/" : "https://www.doubao.com/work/"
        case .manual: return
        }
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    func authorizeClaude() async {
        guard !demoMode, let id = subscriptions.first(where: { $0.provider == .claude && $0.enabled })?.id,
              !refreshing.contains(id) else { return }
        providers[.claude] = ClaudeProvider(allowKeychainPrompt: true)
        lastAttempt[.claude] = nil
        await refresh(id: id)
        providers[.claude] = ClaudeProvider()
    }

    func checkForUpdates() async {
        guard !checkingUpdate else { return }
        checkingUpdate = true
        defer { checkingUpdate = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/NginxL/AgentMeter/releases/latest")!)
            request.timeoutInterval = 15
            request.setValue("AgentMeter", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                updateMessage = text("尚无公开发布版本。", "No public release is available yet.")
                return
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { throw MeterFailure.invalidResponse("update") }
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            if MeterPolicy.isNewerVersion(tag, than: current) {
                updateMessage = text("发现 \(tag)，已打开官方发布页。下载后退出并替换 App 即可更新。", "\(tag) is available. Download it from the release page, quit AgentMeter, and replace the app.")
                NSWorkspace.shared.open(URL(string: "https://github.com/NginxL/AgentMeter/releases/latest")!)
            } else {
                updateMessage = text("当前已是最新版本 \(current)。", "You're up to date: \(current).")
            }
        } catch {
            updateMessage = text("无法检查更新，请稍后重试或访问 GitHub 发布页。", "Couldn't check for updates. Try again or visit GitHub Releases.")
        }
    }

    private func persist() {
        guard !demoMode else { return }
        if let data = try? JSONEncoder().encode(subscriptions) { defaults.set(data, forKey: "subscriptions") }
        // Cache quota data, never credential material or account identifiers.
        let sanitized = snapshots.mapValues { value in
            var copy = value; copy.accountID = nil; return copy
        }
        if let data = try? JSONEncoder().encode(sanitized) { defaults.set(data, forKey: "snapshots") }
    }

    private func message(for failure: MeterFailure) -> String {
        if language != "en" { return failure.localizedDescription }
        switch failure {
        case .notInstalled(let name): return "Install \(name) CLI first, then sign in with your subscription."
        case .notSignedIn(let name): return "Sign in to your subscription in the official \(name) client."
        case .unsupportedAccount(let name): return "Automatic \(name) usage currently supports personal accounts only. Use manual tracking for this account type."
        case .expired(let name): return "Your \(name) login has expired. Sign in again through the official client."
        case .timedOut: return "The request timed out. Try again later."
        case .rateLimited: return "The provider is rate-limiting requests. Try again later."
        case .unavailable, .invalidResponse: return "Usage is unavailable. Check your login and connection; this plan may not expose quota data."
        }
    }
}
