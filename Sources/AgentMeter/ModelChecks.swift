import Foundation
import MeterCore

/// Offline integration checks. Uses a disposable preferences domain and synthetic providers only.
@MainActor
enum ModelChecks {
    static func run() async -> Bool {
        let domain = "io.github.nginxl.AgentMeter.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var count = 0
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            count += 1
            if !condition { failures += 1; print("FAIL: \(label)") }
        }
        let provider = FakeMeterProvider()
        let model = AppModel(defaults: defaults, providers: [.codex: provider], startTimer: false)
        check(model.subscriptions.map(\.provider) == [.codex, .claude], "Fresh installs contain only Codex and Claude")
        let id = model.subscriptions.first(where: { $0.provider == .codex })!.id
        await model.refresh(id: id)
        check(model.snapshots[id]?.windows.first?.usedPercent == 25, "Live results reach the matching subscription")
        check(!model.stale(snapshot: model.snapshots[id]!), "Successful session reads are current")
        let cached = defaults.data(forKey: "snapshots").map { String(decoding: $0, as: UTF8.self) } ?? ""
        check(!cached.contains("private-test-account"), "Stored snapshots omit account identifiers")
        let cacheReload = AppModel(defaults: defaults, providers: [.codex: provider], startTimer: false)
        check(cacheReload.snapshots[id] != nil && cacheReload.stale(snapshot: cacheReload.snapshots[id]!), "Recently saved cache is stale until the current login is verified")
        cacheReload.setDemoMode(true); cacheReload.setDemoMode(false)
        check(cacheReload.stale(snapshot: cacheReload.snapshots[id]!), "Demo round-trip cannot validate an unverified disk cache")
        await cacheReload.refresh(id: id)
        check(!cacheReload.stale(snapshot: cacheReload.snapshots[id]!), "Refreshing a loaded cache validates it for this session")
        let realNames = model.subscriptions.map(\.name)
        let beforeDemo = defaults.data(forKey: "subscriptions")
        let realLanguage = model.language
        let realAutoRefresh = model.autoRefresh
        let savedLanguage = defaults.string(forKey: "language")
        let savedAutoRefresh = defaults.object(forKey: "autoRefresh") as? Bool
        model.setDemoMode(true)
        check(model.subscriptions.map(\.provider) == [.codex, .claude, .manual], "Demo contains two automatic subscriptions and one custom subscription")
        check(model.snapshots.values.allSatisfy { !model.stale(snapshot: $0) }, "Explicit demo snapshots appear current")
        model.language = realLanguage == "zh" ? "en" : "zh"
        model.autoRefresh = !realAutoRefresh
        check(defaults.string(forKey: "language") == savedLanguage && (defaults.object(forKey: "autoRefresh") as? Bool) == savedAutoRefresh, "Demo preferences do not overwrite saved preferences")
        model.save(Subscription(provider: .manual, name: "Demo-only entry", monthlyCost: 5))
        check(defaults.data(forKey: "subscriptions") == beforeDemo, "Editing demo data does not overwrite real preferences")
        model.setDemoMode(false)
        check(model.subscriptions.map(\.name) == realNames, "Leaving demo restores real subscriptions")
        check(!model.stale(snapshot: model.snapshots[id]!), "Leaving demo restores live session validation")
        check(model.language == realLanguage && model.autoRefresh == realAutoRefresh, "Leaving demo restores real language and refresh policy")
        let settingsReload = AppModel(defaults: defaults, providers: [:], startTimer: false)
        check(settingsReload.language == realLanguage && settingsReload.autoRefresh == realAutoRefresh, "Relaunch preserves pre-demo language and refresh policy")
        await provider.setMode(1)
        await model.refresh(id: id)
        check(model.snapshots[id]?.windows.first?.usedPercent == 25 && model.errors[id] != nil, "Network failures retain the last captured quota with an error")
        check(model.stale(snapshot: model.snapshots[id]!), "A failed refresh marks retained data stale")
        defaults.set(false, forKey: "autoRefresh")
        let failureReload = AppModel(defaults: defaults, providers: [:], startTimer: false)
        check(!failureReload.autoRefresh && failureReload.snapshots[id] != nil && failureReload.stale(snapshot: failureReload.snapshots[id]!), "A failed reading stays stale after relaunch when automatic refresh is disabled")
        model.setDemoMode(true); model.setDemoMode(false)
        await provider.setMode(2)
        await model.refresh(id: id)
        check(model.snapshots[id] == nil && model.errors[id] != nil, "Expired login clears old quota rather than displaying a current allowance")
        var extra = Subscription(provider: .manual, name: "Gemini", renewalDate: Date(timeIntervalSince1970: 1800000000), monthlyCost: 15, currency: "EUR")
        model.save(extra)
        let reloaded = AppModel(defaults: defaults, providers: [:], startTimer: false)
        check(reloaded.subscriptions.contains(extra), "Manual renewal date and cost survive relaunch")
        extra.enabled = false
        model.save(extra)
        check(model.subscriptions.first(where: { $0.id == extra.id })?.enabled == false, "Subscriptions can be disabled")
        model.delete(id: extra.id)
        check(!model.subscriptions.contains(where: { $0.id == extra.id }), "Deleting a subscription removes only that entry")

        model.setDemoMode(true); model.setDemoMode(false)
        await provider.setMode(3)
        let pending = Task { await model.refresh(id: id) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        model.setDemoMode(true)
        let demoIDs = Set(model.snapshots.keys)
        await pending.value
        check(Set(model.snapshots.keys) == demoIDs && model.snapshots[id] == nil, "An in-flight real result cannot leak into a demo screenshot")
        model.setDemoMode(false)
        check(model.refreshing.isEmpty, "Switching demo modes clears obsolete loading states")
        check(model.language == "zh", "Fresh installs default to Chinese")
        var manual = Subscription(provider: .manual, name: "Custom tool")
        let recorded = Date(timeIntervalSince1970: 1800000000)
        manual.manualUsage = ManualUsage(windows: [QuotaWindow(id: "manual.weekly", title: "Weekly", usedPercent: 37)], recordedAt: recorded)
        model.save(manual)
        check(manual.usesManualUsage && model.snapshot(for: manual)?.windows.first?.remainingPercent == 63, "Custom subscriptions present explicitly recorded quota")
        check(model.snapshot(for: manual)?.source == "Manual" && model.snapshot(for: manual)?.fetchedAt == recorded, "Manual readings retain their source and recorded timestamp")
        await model.refresh(id: manual.id)
        check(model.snapshots[manual.id] == nil && !model.refreshing.contains(manual.id), "Manual-only providers never start automatic requests")
        let manualReload = AppModel(defaults: defaults, providers: [:], startTimer: false)
        check(manualReload.subscriptions.first(where: { $0.id == manual.id })?.manualUsage == manual.manualUsage, "Recorded manual quota survives relaunch")
        var codexOverride = model.subscriptions.first(where: { $0.id == id })!
        codexOverride.manualTracking = true
        codexOverride.manualUsage = manual.manualUsage
        model.save(codexOverride)
        await provider.setMode(0)
        await model.refresh(id: id)
        check(model.snapshots[id] == nil && model.snapshot(for: codexOverride)?.source == "Manual", "Manual override cannot be overwritten by a provider refresh")
        await checkLegacyMigration(check)
        print("\(count) model checks, \(failures) failures")
        return failures == 0
    }

    private static func checkLegacyMigration(_ check: (Bool, String) -> Void) async {
        let domain = "io.github.nginxl.AgentMeter.migration-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let recorded = Date(timeIntervalSince1970: 1800000000)
        let usage = ManualUsage(windows: [QuotaWindow(id: "manual.weekly", title: "Weekly", usedPercent: 37)], recordedAt: recorded)
        let codex = Subscription(provider: .codex, name: "Work Codex", plan: "Plus", renewalDate: recorded,
            renewalKind: .expires, monthlyCost: 20, currency: "USD", notes: "Keep this note")
        let claude = Subscription(provider: .claude, name: "Claude", plan: "Pro", monthlyCost: 18, currency: "EUR", enabled: false)
        // Same-name custom records must survive: migration keys off provider, never labels.
        let custom = Subscription(provider: .manual, name: "TRAE SOLO CN", plan: "Custom plan", renewalDate: recorded,
            monthlyCost: 88, currency: "CNY", notes: "User-owned record", manualUsage: usage)
        let otherCustom = Subscription(provider: .manual, name: "豆包工作", manualUsage: usage)
        let legacyTrae = Subscription(provider: .trae, name: "Renamed legacy provider", manualTracking: true, manualUsage: usage)
        let legacyDoubao = Subscription(provider: .doubao, name: "Legacy provider", enabled: false, manualUsage: usage)
        let kept = [codex, claude, custom, otherCustom]
        let oldSubscriptions = [legacyTrae, codex, claude, custom, legacyDoubao, otherCustom]
        let keptSnapshots = [
            codex.id: UsageSnapshot(provider: .codex, plan: "Plus", windows: usage.windows, fetchedAt: recorded, source: "Test"),
            claude.id: UsageSnapshot(provider: .claude, windows: usage.windows, fetchedAt: recorded, source: "Test"),
            custom.id: UsageSnapshot(provider: .manual, windows: usage.windows, fetchedAt: recorded, source: "Manual")
        ]
        let removedSnapshot = UsageSnapshot(provider: .trae, windows: usage.windows, fetchedAt: recorded, source: "Legacy test")
        var oldSnapshots = keptSnapshots
        oldSnapshots[legacyTrae.id] = removedSnapshot
        oldSnapshots[legacyDoubao.id] = UsageSnapshot(provider: .doubao, windows: usage.windows, source: "Legacy test")
        oldSnapshots[UUID()] = removedSnapshot
        oldSnapshots[otherCustom.id] = removedSnapshot
        do {
            let subscriptionsData = try JSONEncoder().encode(oldSubscriptions)
            let snapshotsData = try JSONEncoder().encode(oldSnapshots)
            defaults.set(subscriptionsData, forKey: "subscriptions")
            defaults.set(snapshotsData, forKey: "snapshots")
            defaults.set("en", forKey: "language")
            defaults.set(false, forKey: "autoRefresh")
            defaults.set("Unrelated setting", forKey: "untouchedPreference")
            let retiredTrae = FakeMeterProvider(kind: .trae)
            let retiredDoubao = FakeMeterProvider(kind: .doubao)
            let codexProvider = FakeMeterProvider()
            let model = AppModel(defaults: defaults, providers: [.codex: codexProvider, .trae: retiredTrae, .doubao: retiredDoubao], startTimer: false)
            check(model.subscriptions == kept, "Migration preserves every field and ordering of Codex, Claude, and custom subscriptions")
            check(model.snapshots == keptSnapshots, "Migration removes retired caches, including orphaned and mismatched entries, while retaining supported cache")
            check(model.language == "en" && !model.autoRefresh && defaults.string(forKey: "untouchedPreference") == "Unrelated setting", "Migration preserves language, refresh policy, and unrelated preferences")
            let savedSubscriptions = try JSONDecoder().decode([Subscription].self, from: defaults.data(forKey: "subscriptions")!)
            let savedSnapshots = try JSONDecoder().decode([UUID: UsageSnapshot].self, from: defaults.data(forKey: "snapshots")!)
            check(savedSubscriptions == kept && savedSnapshots == keptSnapshots, "Migration writes cleaned subscriptions and cache to disk before a refresh")
            let reloaded = AppModel(defaults: defaults, providers: [:], startTimer: false)
            check(reloaded.subscriptions == kept && reloaded.snapshots == keptSnapshots, "Migration remains stable on relaunch")
            model.save(legacyTrae); model.save(legacyDoubao)
            check(model.subscriptions == kept, "Removed built-in providers cannot be saved again")
            await model.refreshAll()
            await model.refresh(id: legacyTrae.id)
            await model.refresh(id: legacyDoubao.id)
            let activeCalls = await codexProvider.fetchCount
            let retiredTraeCalls = await retiredTrae.fetchCount
            let retiredDoubaoCalls = await retiredDoubao.fetchCount
            check(activeCalls == 1 && retiredTraeCalls == 0 && retiredDoubaoCalls == 0, "Automatic and direct refresh never call removed providers while Codex still refreshes")
            // Starting directly in demo must still clean real data and restore it on exit.
            defaults.set(subscriptionsData, forKey: "subscriptions")
            defaults.set(snapshotsData, forKey: "snapshots")
            let demo = AppModel(demo: true, defaults: defaults, providers: [:], startTimer: false)
            let demoSaved = try JSONDecoder().decode([Subscription].self, from: defaults.data(forKey: "subscriptions")!)
            check(demoSaved == kept, "Launching into demo persists the real-data migration first")
            demo.setDemoMode(false)
            check(demo.subscriptions == kept && demo.snapshots == keptSnapshots && demo.language == "en" && !demo.autoRefresh, "Leaving demo restores migrated subscriptions, cache, and preferences")
        } catch {
            check(false, "Legacy migration fixture failed: \(error)")
        }
    }
}

private actor FakeMeterProvider: UsageProvider {
    nonisolated let kind: ProviderKind
    private(set) var fetchCount = 0
    var mode = 0
    init(kind: ProviderKind = .codex) { self.kind = kind }
    func setMode(_ value: Int) { mode = value }
    func fetch() async throws -> UsageSnapshot {
        fetchCount += 1
        switch mode {
        case 1: throw MeterFailure.unavailable("Synthetic offline condition")
        case 2: throw MeterFailure.expired("Codex")
        case 3: try await Task.sleep(nanoseconds: 150_000_000)
        default: break
        }
        return UsageSnapshot(provider: .codex, plan: "Test", windows: [QuotaWindow(id: "test", title: "5 hours", usedPercent: 25)], source: "Test", accountID: "private-test-account")
    }
}
