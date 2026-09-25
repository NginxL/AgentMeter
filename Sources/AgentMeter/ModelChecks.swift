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
        var doubao = model.subscriptions.first(where: { $0.provider == .doubao })!
        let recorded = Date(timeIntervalSince1970: 1800000000)
        doubao.manualUsage = ManualUsage(windows: [QuotaWindow(id: "manual.weekly", title: "Weekly", usedPercent: 37)], recordedAt: recorded)
        model.save(doubao)
        check(doubao.usesManualUsage && model.snapshot(for: doubao)?.windows.first?.remainingPercent == 63, "Doubao presents explicitly recorded quota")
        check(model.snapshot(for: doubao)?.source == "Manual" && model.snapshot(for: doubao)?.fetchedAt == recorded, "Manual readings retain their source and recorded timestamp")
        await model.refresh(id: doubao.id)
        check(model.snapshots[doubao.id] == nil && !model.refreshing.contains(doubao.id), "Manual-only providers never start automatic requests")
        let manualReload = AppModel(defaults: defaults, providers: [:], startTimer: false)
        check(manualReload.subscriptions.first(where: { $0.id == doubao.id })?.manualUsage == doubao.manualUsage, "Recorded manual quota survives relaunch")
        var codexOverride = model.subscriptions.first(where: { $0.id == id })!
        codexOverride.manualTracking = true
        codexOverride.manualUsage = doubao.manualUsage
        model.save(codexOverride)
        await provider.setMode(0)
        await model.refresh(id: id)
        check(model.snapshots[id] == nil && model.snapshot(for: codexOverride)?.source == "Manual", "Manual override cannot be overwritten by a provider refresh")
        model.language = "en"
        check(model.displayName(doubao) == "Doubao Work", "Default Doubao label switches to English")
        model.language = "zh"
        check(model.displayName(doubao) == "豆包工作", "Default Doubao label switches to Chinese")
        print("\(count) model checks, \(failures) failures")
        return failures == 0
    }
}

private actor FakeMeterProvider: UsageProvider {
    nonisolated let kind: ProviderKind = .codex
    var mode = 0
    func setMode(_ value: Int) { mode = value }
    func fetch() async throws -> UsageSnapshot {
        switch mode {
        case 1: throw MeterFailure.unavailable("Synthetic offline condition")
        case 2: throw MeterFailure.expired("Codex")
        case 3: try await Task.sleep(nanoseconds: 150_000_000)
        default: break
        }
        return UsageSnapshot(provider: .codex, plan: "Test", windows: [QuotaWindow(id: "test", title: "5 hours", usedPercent: 25)], source: "Test", accountID: "private-test-account")
    }
}
