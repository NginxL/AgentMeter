import SwiftUI
import MeterCore

enum MeterStyle {
    static let background = Color(red: 0.956, green: 0.969, blue: 0.980)
    static let ink = Color(red: 0.105, green: 0.165, blue: 0.204)
    static let secondary = Color(red: 0.43, green: 0.49, blue: 0.54)
    static let accent = Color(red: 0.10, green: 0.48, blue: 0.41)
    static let line = Color(red: 0.89, green: 0.92, blue: 0.94)
    static let amber = Color(red: 0.72, green: 0.43, blue: 0.12)

    static func providerColor(_ provider: ProviderKind) -> Color {
        switch provider {
        case .codex: return accent
        case .claude: return Color(red: 0.75, green: 0.43, blue: 0.31)
        default: return Color(red: 0.39, green: 0.42, blue: 0.68)
        }
    }
}

struct MeterCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MeterStyle.line.opacity(0.8), lineWidth: 1))
    }
}

struct ProviderMark: View {
    var provider: ProviderKind
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(MeterStyle.providerColor(provider).opacity(0.11))
            Image(systemName: symbol)
                .font(.system(size: size * 0.47, weight: .medium))
                .foregroundStyle(MeterStyle.providerColor(provider))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch provider {
        case .codex: return "terminal"
        case .claude: return "sun.max"
        default: return "square.stack.3d.up"
        }
    }
}

struct AppMark: View {
    var size: CGFloat = 37
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(MeterStyle.accent)
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct MeterPill: View {
    var text: String
    var color: Color = MeterStyle.secondary
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.09), in: Capsule())
    }
}

struct MeterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .foregroundStyle(prominent ? .white : MeterStyle.ink)
            .background(prominent ? MeterStyle.accent : Color.white, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(prominent ? MeterStyle.accent : MeterStyle.line, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }
}

func meterDate(_ date: Date, language: String, includeTime: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language == "zh" ? "zh_CN" : "en_US")
    formatter.dateFormat = language == "zh" ? (includeTime ? "M月d日 HH:mm" : "yyyy年M月d日") : (includeTime ? "MMM d, h:mm a" : "MMM d, yyyy")
    return formatter.string(from: date)
}

func meterCost(_ cost: Double?, currency: String) -> String {
    guard let cost else { return "—" }
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.maximumFractionDigits = cost.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
    return formatter.string(from: NSNumber(value: cost)) ?? "\(currency) \(cost)"
}

@MainActor
func quotaTitle(_ window: QuotaWindow, model: AppModel) -> String {
    let title = window.title.lowercased()
    if title.contains("5") && (title.contains("hour") || title.contains("小时")) { return model.text("5 小时额度", "5-hour limit") }
    if title == "weekly" || title == "week" || title == "每周额度" || title == "周额度" || title == "7-day" || title == "7 天" || title == "7天" { return model.text("每周额度", "Weekly limit") }
    if title == "session" || title == "当前会话" { return model.text("当前会话", "Current session") }
    if title == "current period" || title == "当前时段" { return model.text("当前时段", "Current period") }
    if title == "主要窗口" { return model.text("主要窗口", "Primary limit") }
    if title == "次要窗口" { return model.text("次要窗口", "Secondary limit") }
    if model.language == "en" {
        return window.title
            .replacingOccurrences(of: "小时", with: "hours")
            .replacingOccurrences(of: "分钟", with: "minutes")
            .replacingOccurrences(of: "天", with: "days")
    }
    return window.title
}

@MainActor
func planTitle(_ plan: String, model: AppModel) -> String {
    model.demoMode && plan == "Example" ? model.text("示例套餐", "Example plan") : plan
}
