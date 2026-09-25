import SwiftUI
import MeterCore

struct ManualQuotaDraft: Identifiable {
    var id: String
    var title: String
    var usedText: String
    var hasReset: Bool
    var resetDate: Date

    init(window: QuotaWindow? = nil, title: String = "") {
        id = window?.id ?? "manual.\(UUID().uuidString)"
        self.title = window?.title ?? title
        usedText = window?.usedPercent.map { String($0) } ?? ""
        hasReset = window?.resetsAt != nil
        resetDate = window?.resetsAt ?? Date()
    }

    var hasData: Bool { !usedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasReset }
    var percentValid: Bool {
        let text = usedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }
        guard let value = Double(text) else { return false }
        return value.isFinite && (0...100).contains(value)
    }
    var isValid: Bool { percentValid && (!hasData || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    var window: QuotaWindow? {
        guard hasData, isValid else { return nil }
        return QuotaWindow(id: id, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                           usedPercent: Double(usedText.trimmingCharacters(in: .whitespacesAndNewlines)),
                           resetsAt: hasReset ? resetDate : nil)
    }
}

struct ManualUsageEditor: View {
    @ObservedObject var model: AppModel
    @Binding var rows: [ManualQuotaDraft]
    var recordedAt: Date?
    var provider: ProviderKind

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(model.text("手动额度记录", "Manual usage record"), systemImage: "pencil.line")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                MeterPill(text: model.text("不自动更新", "No auto-refresh"), color: MeterStyle.amber)
            }
            Text(model.text("按官方页面填写已用比例。最多记录两个额度窗口；留空表示未知。", "Enter the used percentage from the provider. Track up to two windows; leave unknown values blank."))
                .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            ForEach($rows) { $row in
                ManualQuotaRow(model: model, row: $row) {
                    let rowID = row.id
                    rows.removeAll { $0.id == rowID }
                }
            }
            HStack {
                if rows.count < 2 {
                    Button {
                        rows.append(ManualQuotaDraft(title: rows.isEmpty ? model.text("当前时段", "Current period") : model.text("7 天", "7 days")))
                    } label: {
                        Label(model.text("添加额度窗口", "Add usage window"), systemImage: "plus")
                    }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(MeterStyle.accent)
                }
                Spacer()
                if provider != .manual {
                    Button { model.openDashboard(provider) } label: {
                        Label(model.text("官方用量入口", "Official usage"), systemImage: "arrow.up.right")
                    }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(MeterStyle.accent)
                }
            }
            if let recordedAt {
                Text(model.text("上次记录：", "Last recorded: ") + meterDate(recordedAt, language: model.language, includeTime: true))
                    .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
            }
        }
        .padding(15)
        .background(MeterStyle.providerColor(provider).opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MeterStyle.line))
    }
}

private struct ManualQuotaRow: View {
    @ObservedObject var model: AppModel
    @Binding var row: ManualQuotaDraft
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text("窗口名称", "Window label")).font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
                    TextField(model.text("例如当前时段、7 天", "e.g. Current period, 7 days"), text: $row.title)
                        .accessibilityLabel(model.text("额度窗口名称", "Usage window label"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text("已用比例（%）", "Used (%)")).font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
                    TextField("0–100", text: $row.usedText)
                        .accessibilityLabel(model.text("已用百分比", "Used percentage"))
                }.frame(width: 103)
                Button(action: remove) { Image(systemName: "minus.circle").padding(4) }
                    .buttonStyle(.plain).foregroundStyle(MeterStyle.secondary)
                    .help(model.text("移除此额度窗口", "Remove this usage window"))
                    .padding(.top, 22)
            }
            if !row.percentValid {
                Text(model.text("已用比例须为 0 到 100 之间的数字。", "Used percentage must be a number from 0 to 100."))
                    .font(.system(size: 10)).foregroundStyle(.red)
            } else if row.hasData && row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(model.text("请填写额度窗口名称。", "Enter a label for this usage window."))
                    .font(.system(size: 10)).foregroundStyle(.red)
            }
            HStack(spacing: 12) {
                Toggle(model.text("重置时间", "Reset time"), isOn: $row.hasReset)
                    .font(.system(size: 11)).toggleStyle(.checkbox).controlSize(.small)
                Spacer(minLength: 0)
                if row.hasReset {
                    DatePicker(model.text("额度重置时间", "Usage reset time"), selection: $row.resetDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden().datePickerStyle(.field).controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(MeterStyle.line))
    }
}
