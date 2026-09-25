import SwiftUI
import MeterCore

struct SubscriptionEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Subscription
    @State private var hasDate: Bool
    @State private var billingDate: Date
    @State private var amount: String
    @State private var manualRows: [ManualQuotaDraft]
    @State private var confirmDelete = false

    init(model: AppModel, subscription: Subscription) {
        self.model = model
        _draft = State(initialValue: subscription)
        _hasDate = State(initialValue: subscription.renewalDate != nil)
        _billingDate = State(initialValue: subscription.renewalDate ?? Date())
        _amount = State(initialValue: subscription.monthlyCost.map { String(format: "%g", $0) } ?? "")
        let rows = subscription.manualUsage?.windows.map { ManualQuotaDraft(window: $0) } ?? []
        _manualRows = State(initialValue: rows.isEmpty ? [ManualQuotaDraft(title: model.text("当前时段", "Current period"))] : rows)
    }

    private var isExisting: Bool { model.subscriptions.contains { $0.id == draft.id } }
    private var numericAmount: Double? { Double(amount.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var amountValid: Bool {
        amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (numericAmount != nil && numericAmount!.isFinite && numericAmount! >= 0)
    }
    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amountValid && draft.currency.count == 3 && draft.currency.allSatisfy(\.isLetter)
            && (!draft.usesManualUsage || manualRows.allSatisfy(\.isValid))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ProviderMark(provider: draft.provider)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isExisting ? model.text("编辑订阅", "Edit subscription") : model.text("添加订阅", "Add subscription"))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text(model.text("把套餐、费用和下一账期记录在一起。", "Keep your plan, price, and billing date together."))
                        .font(.system(size: 11)).foregroundStyle(MeterStyle.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 12)).padding(8) }
                    .buttonStyle(.plain).foregroundStyle(MeterStyle.secondary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    connectionFields
                    HStack(alignment: .top, spacing: 14) {
                        field(model.text("工具名称", "Tool name")) {
                            TextField(model.text("例如 Cursor、Gemini", "e.g. Cursor, Gemini"), text: $draft.name)
                        }
                        field(model.text("套餐名称", "Plan name")) {
                            TextField(model.text("例如 Pro、Plus", "e.g. Pro, Plus"), text: $draft.plan)
                        }
                    }
                    if draft.usesManualUsage {
                        ManualUsageEditor(model: model, rows: $manualRows, recordedAt: draft.manualUsage?.recordedAt, provider: draft.provider)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        field(model.text("月费（可选）", "Monthly cost (optional)")) {
                            TextField("0.00", text: $amount)
                                .accessibilityLabel(model.text("月费", "Monthly cost"))
                            if !amountValid {
                                Text(model.text("请输入不小于 0 的金额", "Enter an amount of zero or more"))
                                    .font(.system(size: 10)).foregroundStyle(.red)
                            }
                        }
                        field(model.text("币种", "Currency")) {
                            Picker(model.text("币种", "Currency"), selection: $draft.currency) {
                                ForEach(["USD", "CNY", "EUR", "GBP", "JPY", "HKD", "TWD", "KRW", "CAD", "AUD", "SGD"], id: \.self) { currency in
                                    Text(currency).tag(currency)
                                }
                                if !["USD", "CNY", "EUR", "GBP", "JPY", "HKD", "TWD", "KRW", "CAD", "AUD", "SGD"].contains(draft.currency) {
                                    Text(draft.currency).tag(draft.currency)
                                }
                            }.labelsHidden().frame(maxWidth: .infinity)
                        }.frame(width: 132)
                    }
                    billingFields
                    field(model.text("备注（可选）", "Notes (optional)")) {
                        TextEditor(text: $draft.notes)
                            .font(.system(size: 12))
                            .frame(height: 63)
                            .padding(5)
                            .scrollContentBackground(.hidden)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MeterStyle.line))
                    }
                    Toggle(isOn: $draft.enabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.text("启用此订阅", "Enable this subscription")).font(.system(size: 12, weight: .medium))
                            Text(model.text("停用后保留记录，不计入总览或刷新额度。", "Disabled plans stay saved and are excluded from totals and refreshes."))
                                .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary)
                        }
                    }.toggleStyle(.switch).controlSize(.small)
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .padding(24)
            }.frame(maxHeight: 505)
            Divider()
            HStack {
                if isExisting {
                    Button(model.text("删除订阅", "Delete plan"), role: .destructive) { confirmDelete = true }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.red)
                }
                Spacer()
                Button(model.text("取消", "Cancel")) { dismiss() }.buttonStyle(MeterButtonStyle())
                Button(model.text("保存订阅", "Save plan")) { save() }
                    .buttonStyle(MeterButtonStyle(prominent: true)).disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 24).padding(.vertical, 18)
        }
        .foregroundStyle(MeterStyle.ink)
        .background(MeterStyle.background)
        .frame(width: 530)
        .alert(model.text("删除这份订阅？", "Delete this subscription?"), isPresented: $confirmDelete) {
            Button(model.text("取消", "Cancel"), role: .cancel) { }
            Button(model.text("删除", "Delete"), role: .destructive) {
                model.delete(id: draft.id)
                dismiss()
            }
        } message: {
            Text(model.text("只会删除 AgentMeter 中的记录，不会取消服务商的订阅。", "This removes the record from AgentMeter. It does not cancel your subscription with the provider."))
        }
    }

    private var connectionFields: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !isExisting {
                field(model.text("读取方式", "Usage tracking")) {
                    Picker(model.text("读取方式", "Usage tracking"), selection: $draft.provider) {
                        Text(model.text("任意工具 · 手动管理", "Any tool · Manual")).tag(ProviderKind.manual)
                        if !model.subscriptions.contains(where: { $0.provider == .codex }) {
                            Text("Codex · " + model.text("自动读取", "Automatic")).tag(ProviderKind.codex)
                        }
                        if !model.subscriptions.contains(where: { $0.provider == .claude }) {
                            Text("Claude · " + model.text("自动读取", "Automatic")).tag(ProviderKind.claude)
                        }
                        if !model.subscriptions.contains(where: { $0.provider == .trae }) {
                            Text("TRAE SOLO CN · " + model.text("自动读取（实验性）", "Automatic (experimental)")).tag(ProviderKind.trae)
                        }
                        if !model.subscriptions.contains(where: { $0.provider == .doubao }) {
                            Text(model.text("豆包工作 · 手动记录", "Doubao Work · Manual")).tag(ProviderKind.doubao)
                        }
                    }.labelsHidden()
                    .onChange(of: draft.provider) { old, new in
                        if draft.name.isEmpty || draft.name == old.name || (old == .doubao && draft.name == "豆包工作") {
                            draft.name = new == .manual ? "" : (new == .doubao ? "豆包工作" : new.name)
                        }
                        if new == .trae || new == .doubao { draft.currency = "CNY" }
                    }
                }
            }
            if draft.provider.supportsAutomaticUsage {
                Toggle(isOn: Binding(get: { draft.usesManualUsage }, set: { draft.manualTracking = $0 })) {
                    Text(model.text("改为手动记录额度", "Track usage manually"))
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.toggleStyle(.switch).controlSize(.small)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: draft.usesManualUsage ? "pencil.line" : "link").font(.system(size: 12))
                Text(connectionDescription)
                    .font(.system(size: 11)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(draft.usesManualUsage ? MeterStyle.secondary : MeterStyle.accent)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MeterStyle.providerColor(draft.provider).opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var connectionDescription: String {
        if draft.usesManualUsage {
            return model.text("手动记录：额度不会自动刷新。套餐、费用及续费日期也由你维护。", "Manual records do not refresh automatically. Plan, cost, and billing dates are also maintained by you.")
        }
        if draft.provider == .trae {
            return model.text("实验性读取 TRAE SOLO CN 个人额度；企业额度暂不支持。也可切换为手动记录。", "Experimental access to TRAE SOLO CN personal usage. Enterprise quotas are not supported; manual tracking is available.")
        }
        return model.text("额度从本机的官方登录读取。套餐、费用及账期由你手动维护。", "Usage comes from your official local login. Plan, cost, and billing details are maintained by you.")
    }

    private var billingFields: some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle(model.text("记录续费或到期日期", "Track a renewal or expiry date"), isOn: $hasDate)
                .font(.system(size: 12, weight: .medium)).toggleStyle(.switch).controlSize(.small)
            if hasDate {
                HStack(spacing: 12) {
                    Picker(model.text("账期类型", "Billing type"), selection: $draft.renewalKind) {
                        Text(model.text("续费日期", "Renews on")).tag(RenewalKind.renews)
                        Text(model.text("到期日期", "Expires on")).tag(RenewalKind.expires)
                    }.labelsHidden().frame(width: 145)
                    DatePicker(model.text("日期", "Date"), selection: $billingDate, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field)
                    Spacer(minLength: 0)
                }
            }
            Text(model.text("订阅账期与额度重置时间独立，请分别核对。", "Billing dates and usage reset times are separate; confirm each independently."))
                .font(.system(size: 10)).foregroundStyle(MeterStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MeterStyle.line))
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(MeterStyle.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        draft.renewalDate = hasDate ? billingDate : nil
        draft.monthlyCost = amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : numericAmount
        if draft.usesManualUsage {
            let windows = manualRows.compactMap(\.window)
            if windows.isEmpty { draft.manualUsage = nil }
            else if windows != draft.manualUsage?.windows {
                draft.manualUsage = ManualUsage(windows: windows, recordedAt: Date())
            }
        }
        model.save(draft)
        dismiss()
    }
}
