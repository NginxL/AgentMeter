import AppKit
import MeterCore
import MeterProviders
import SwiftUI

@main
enum AgentMeterMain {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--self-check") {
            Task { exit(await ModelChecks.run() ? 0 : 1) }
            RunLoop.main.run()
            return
        }
        if let index = arguments.firstIndex(of: "--probe"), arguments.indices.contains(index + 1) {
            let kind = arguments[index + 1]
            Task {
                do {
                    let provider: any UsageProvider
                    switch kind {
                    case "codex": provider = CodexProvider()
                    case "claude": provider = ClaudeProvider()
                    case "trae": provider = TraeProvider()
                    default: print("Supported probes: codex, claude, trae"); exit(2)
                    }
                    var snapshot = try await provider.fetch()
                    snapshot.accountID = nil
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(snapshot)
                    print(String(decoding: data, as: UTF8.self))
                    exit(0)
                } catch {
                    print((error as? MeterFailure)?.localizedDescription ?? "Usage unavailable; no credential details are logged.")
                    exit(1)
                }
            }
            RunLoop.main.run()
            return
        }
        if let index = arguments.firstIndex(of: "--render-screenshots"), arguments.indices.contains(index + 1) {
            renderScreenshots(to: arguments[index + 1])
            return
        }
        AgentMeterApplication.main()
    }

    @MainActor
    private static func renderScreenshots(to directory: String) {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.appearance = NSAppearance(named: .aqua)
        let model = AppModel(demo: true, startTimer: false)
        model.language = "en"
        let host = NSHostingView(rootView: DashboardView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AgentMeter · Demo"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                for language in ["en", "zh"] {
                model.language = language
                for (tab, height) in [("overview", 1160.0), ("subscriptions", 760.0), ("settings", 1230.0)] {
                    let filename = tab + (language == "zh" ? "-zh" : "")
                    window.setContentSize(NSSize(width: 1100, height: height))
                    model.selectedTab = tab
                    try await Task.sleep(nanoseconds: 600_000_000)
                    host.layoutSubtreeIfNeeded()
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.coderInvalidValue) }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                    try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(filename).png"))
                }
                }
                print("Rendered native demo screenshots to \(directory)")
                application.terminate(nil)
            } catch { print("Screenshot rendering failed: \(error.localizedDescription)"); exit(1) }
        }
        application.run()
    }
}

struct AgentMeterApplication: App {
    @StateObject private var model: AppModel
    @NSApplicationDelegateAdaptor(MeterAppDelegate.self) private var delegate

    init() {
        _model = StateObject(wrappedValue: AppModel(demo: CommandLine.arguments.contains("--demo")))
    }

    var body: some Scene {
        Window("AgentMeter", id: "main") {
            DashboardView(model: model)
                .frame(minWidth: 920, minHeight: 680)
                .task { if model.autoRefresh { await model.refreshAll() } }
        }
        .defaultSize(width: 1100, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(model.text("检查更新…", "Check for Updates…")) { Task { await model.checkForUpdates() } }
            }
            CommandGroup(after: .toolbar) {
                Button(model.text("刷新额度", "Refresh Usage")) { Task { await model.refreshAll() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        MenuBarExtra("AgentMeter", systemImage: "chart.bar.xaxis") {
            MenuPanelView(model: model)
        }
        .menuBarExtraStyle(.window)
        Settings {
            DashboardView(model: model)
                .frame(width: 1100, height: 800)
                .onAppear { model.selectedTab = "settings" }
        }
    }
}

final class MeterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first(where: { $0.title == "AgentMeter" }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
