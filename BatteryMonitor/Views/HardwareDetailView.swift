import SwiftUI

// MARK: - 硬件原始数据（折叠，给极客看）
//
// 值为 0 / 空数组 / 空字符串的行整行隐藏，而不是显示一堆「—」。整组全空则整组隐藏
// （比如拔电时充电器组、电池供电时瞬时遥测组）。

/// 字段可信度。来自实机 dump 后逐字段核对的结论，不是照文档抄的。
enum FieldReliability {
    case verified      // 实测可靠
    case conditional   // 有前提（如仅插电时有值、单位因机型而异）
    case questionable  // 存疑（语义或单位没解出来）
    case derived       // 我们自己算出来的衍生值

    var badge: String {
        switch self {
        case .verified: return "✓"
        case .conditional: return "◐"
        case .questionable: return "?"
        case .derived: return "ƒ"
        }
    }
    var labelKey: String {
        switch self {
        case .verified: return "hw.rel.verified"
        case .conditional: return "hw.rel.conditional"
        case .questionable: return "hw.rel.questionable"
        case .derived: return "hw.rel.derived"
        }
    }
}

struct HardwareRow: Identifiable {
    let id = UUID()
    let key: String          // registry 字段名，原样给极客看
    let value: String
    let unit: String
    let meaning: String      // 人话解释，一行内显示
    var reliability: FieldReliability = .verified
    /// 长注意事项，走 .help() 悬浮显示 —— 表格一行放不下段落
    var note: String? = nil
}

struct HardwareGroup: Identifiable {
    let id = UUID()
    let titleKey: String
    let rows: [HardwareRow]
}

struct HardwareDetailView: View {
    let detail: BatteryHardwareDetail
    @State private var expanded = false

    private var groups: [HardwareGroup] { Self.build(detail) }
    private var fieldCount: Int { groups.reduce(0) { $0 + $1.rows.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 14 : 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.accentPurple)
                    Text(L("insight.section.hardware"))
                        .font(AppTheme.Typography.sectionTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(L("hw.fields_count", fieldCount))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.contrastOverlay(0.05)))
                    Spacer()
                    Text(detail.architecture.rawValue)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.chargingCyan)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.chargingCyan.opacity(0.1)))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppTheme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerOnHover()

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L(group.titleKey))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AppTheme.chargingCyan.opacity(0.85))
                                .padding(.top, 3)
                            ForEach(group.rows) { row in
                                HStack(spacing: 8) {
                                    Text(row.key)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .frame(width: 190, alignment: .leading)
                                        .lineLimit(1)
                                    Text(row.value)
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .frame(width: 130, alignment: .leading)
                                        .lineLimit(1)
                                    Text(row.unit)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(AppTheme.textTertiary)
                                        .frame(width: 56, alignment: .leading)
                                    Text(row.meaning)
                                        .font(.system(size: 10))
                                        .foregroundStyle(AppTheme.textTertiary)
                                        .lineLimit(1)
                                    if row.note != nil {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 8))
                                            .foregroundStyle(AppTheme.textTertiary.opacity(0.55))
                                    }
                                    Spacer(minLength: 0)
                                    Text(row.reliability.badge)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(badgeColor(row.reliability))
                                        .frame(width: 14)
                                        .help(L(row.reliability.labelKey))
                                }
                                .help(row.note ?? "")
                                .padding(.vertical, 2.5)
                                .padding(.horizontal, 6)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(AppTheme.contrastOverlay(0.02)))
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
        .modifier(AppTheme.hoverLift(accent: AppTheme.accentPurple))
    }

    private func badgeColor(_ r: FieldReliability) -> Color {
        switch r {
        case .verified:      return AppTheme.batteryGreen.opacity(0.75)
        case .conditional:   return AppTheme.batteryYellow.opacity(0.8)
        case .questionable:  return AppTheme.batteryRed.opacity(0.7)
        case .derived:       return AppTheme.accentPurple.opacity(0.85)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L("hw.field")).frame(width: 190, alignment: .leading)
            Text(L("hw.value")).frame(width: 130, alignment: .leading)
            Text(L("hw.unit")).frame(width: 56, alignment: .leading)
            Text(L("hw.meaning"))
            Spacer(minLength: 0)
            Text(L("hw.rel")).frame(width: 14)
        }
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
        .textCase(.uppercase)
    }

    // MARK: - 建表

    static func build(_ d: BatteryHardwareDetail) -> [HardwareGroup] {
        var groups: [HardwareGroup] = []

        func rows(_ items: [HardwareRow?]) -> [HardwareRow] { items.compactMap { $0 } }
        /// 整数行，0 视为不可用则整行隐藏
        func int(_ k: String, _ v: Int, _ u: String, _ m: String, hideZero: Bool = true,
                 _ rel: FieldReliability = .verified, _ note: String? = nil) -> HardwareRow? {
            if hideZero && v == 0 { return nil }
            return HardwareRow(key: k, value: v.formatted(), unit: u, meaning: m, reliability: rel, note: note)
        }
        func dbl(_ k: String, _ v: Double, _ fmt: String, _ u: String, _ m: String,
                 _ rel: FieldReliability = .verified, _ note: String? = nil) -> HardwareRow? {
            guard abs(v) > 0.0001 else { return nil }
            return HardwareRow(key: k, value: LNum(fmt, v), unit: u, meaning: m, reliability: rel, note: note)
        }
        func arr(_ k: String, _ v: [Int], _ u: String, _ m: String,
                 _ rel: FieldReliability = .verified, _ note: String? = nil) -> HardwareRow? {
            guard !v.isEmpty else { return nil }
            return HardwareRow(key: k, value: v.map(String.init).joined(separator: " / "),
                               unit: u, meaning: m, reliability: rel, note: note)
        }
        func str(_ k: String, _ v: String, _ m: String,
                 _ rel: FieldReliability = .verified, _ note: String? = nil) -> HardwareRow? {
            guard !v.isEmpty else { return nil }
            return HardwareRow(key: k, value: v, unit: "—", meaning: m, reliability: rel, note: note)
        }
        func txt(_ k: String, _ v: String, _ u: String, _ m: String,
                 _ rel: FieldReliability = .derived, _ note: String? = nil) -> HardwareRow? {
            HardwareRow(key: k, value: v, unit: u, meaning: m, reliability: rel, note: note)
        }

        // 电芯
        let cells = rows([
            arr("CellVoltage", d.cellVoltages, "mV", L("hw.m.cell_voltage", d.cellVoltages.count), .verified, L("hw.n.cell_voltage")),
            d.cellVoltageDelta.flatMap { int("CellVoltage.delta", $0, "mV", L("hw.m.cell_delta")) },
            arr("WeightedRa", d.weightedRa, "mΩ", L("hw.m.weighted_ra"), .verified, L("hw.n.weighted_ra")),
            arr("Qmax", d.qmax, "mAh", L("hw.m.qmax"), .verified, L("hw.n.qmax")),
            arr("PresentDOD", d.presentDOD, "%", L("hw.m.dod")),
        ])
        if !cells.isEmpty { groups.append(.init(titleKey: "hw.group.cells", rows: cells)) }

        // 容量与寿命
        let cap = rows([
            int("DesignCapacity", d.designCapacity, "mAh", L("hw.m.design_capacity")),
            int("AppleRawMaxCapacity", d.appleRawMaxCapacity, "mAh", L("hw.m.raw_max"), hideZero: true, .verified, L("hw.n.raw_max")),
            int("AppleRawCurrentCapacity", d.appleRawCurrentCapacity, "mAh", L("hw.m.raw_current"), hideZero: true, .verified, L("hw.n.raw_current")),
            int("NominalChargeCapacity", d.nominalChargeCapacity, "mAh", L("hw.m.nominal")),
            int("PackReserve", d.packReserve, "mAh", L("hw.m.reserve"), hideZero: true, .verified, L("hw.n.reserve")),
            int("CycleCount", d.cycleCount, "", L("hw.m.cycles")),
            int("DesignCycleCount9C", d.designCycleCount, "", L("hw.m.design_cycles"), hideZero: true, .verified, L("hw.n.design_cycles")),
            d.systemHealthPercent.flatMap { dbl("→ health (system)", $0, "%.1f", "%", L("hw.m.health_system")) },
            d.rawHealthPercent.flatMap { dbl("→ health (raw)", $0, "%.1f", "%", L("hw.m.health_raw")) },
        ])
        if !cap.isEmpty { groups.append(.init(titleKey: "hw.group.capacity", rows: cap)) }

        // 电气
        let elec = rows([
            int("AppleRawBatteryVoltage", d.packVoltage, "mV", L("hw.m.pack_voltage")),
            int("InstantAmperage", d.instantAmperage, "mA", L("hw.m.instant_amperage"), hideZero: false),
            int("Amperage", d.smoothedAmperage, "mA", L("hw.m.smoothed_amperage"), hideZero: false),
            dbl("VirtualTemperature", d.virtualTemperature, "%.2f", "°C", L("hw.m.virtual_temp"), .conditional, L("hw.n.temp_unit")),
            dbl("BatteryData.SystemPower", d.systemPowerWatts, "%.2f", "W", L("hw.m.system_power"), .verified, L("hw.n.system_power")),
        ])
        if !elec.isEmpty { groups.append(.init(titleKey: "hw.group.electrical", rows: elec)) }

        // 充电器（拔电时整组隐藏）
        let chg = rows([
            int("AdapterDetails.Watts", d.adapterWatts, "W", L("hw.m.adapter_watts")),
            int("AdapterDetails.AdapterVoltage", d.adapterVoltage, "mV", L("hw.m.adapter_voltage")),
            int("AdapterDetails.Current", d.adapterCurrent, "mA", L("hw.m.adapter_current")),
            str("AdapterDetails.Description", d.adapterDescription, L("hw.m.adapter_desc")),
            d.usbHvcMenu.isEmpty ? nil : HardwareRow(
                key: "AdapterDetails.UsbHvcMenu",
                value: d.usbHvcMenu.map { LNum("%.0fV/%.1fA", Double($0.voltage) / 1000, Double($0.current) / 1000) }
                                   .joined(separator: " · "),
                unit: "—", meaning: L("hw.m.pd_menu")),
            int("ChargerData.ChargingVoltage", d.chargingVoltageLimit, "mV", L("hw.m.charge_v_limit")),
            // hideZero 必须为 true：否则拔电时这一行会单独把整个充电器组撑着不隐藏
            int("ChargerData.ChargingCurrent", d.chargingCurrentLimit, "mA", L("hw.m.charge_i_limit"), hideZero: true, .conditional, L("hw.n.charge_i_limit")),
            int("ChargerData.NotChargingReason", d.notChargingReason, "", L("hw.m.not_charging_reason"), hideZero: true, .questionable, L("hw.n.not_charging_reason")),
            int("ChargerData.ChargerID", d.chargerID, "", L("hw.m.charger_id")),
        ])
        if !chg.isEmpty { groups.append(.init(titleKey: "hw.group.charger", rows: chg)) }

        // 功耗遥测（电池供电时瞬时字段为 0，会自动隐藏）
        let tel = rows([
            int("PowerTelemetryData.SystemLoad", d.systemLoad, "mW", L("hw.m.system_load")),
            int("PowerTelemetryData.BatteryPower", d.batteryPower, "mW", L("hw.m.battery_power"), hideZero: false),
            int("PowerTelemetryData.SystemPowerIn", d.systemPowerIn, "mW", L("hw.m.power_in"), hideZero: true, .conditional, L("hw.n.ac_only")),
            int("PowerTelemetryData.SystemVoltageIn", d.systemVoltageIn, "mV", L("hw.m.voltage_in"), hideZero: true, .conditional, L("hw.n.ac_only")),
            int("PowerTelemetryData.SystemCurrentIn", d.systemCurrentIn, "mA", L("hw.m.current_in"), hideZero: true, .conditional, L("hw.n.ac_only")),
            d.adapterEfficiency.flatMap { dbl("→ adapter efficiency", $0, "%.1f", "%", L("hw.m.efficiency")) },
        ])
        if !tel.isEmpty { groups.append(.init(titleKey: "hw.group.telemetry", rows: tel)) }

        // 身份
        let ident = rows([
            str("Serial", d.serialNumber, L("hw.m.serial")),
            str("DeviceName", d.gaugeChip, L("hw.m.gauge_chip")),
            int("GasGaugeFirmwareVersion", d.gaugeFirmwareVersion, "", L("hw.m.gauge_fw")),
            int("BatteryData.ChemID", d.chemistryID, "", L("hw.m.chem_id")),
            int("BatteryData.DataFlashWriteCount", d.dataFlashWriteCount, "", L("hw.m.flash_writes")),
            int("PermanentFailureStatus", d.permanentFailureStatus, "", L("hw.m.pf_status"), hideZero: false),
            int("BatteryCellDisconnectCount", d.cellDisconnectCount, "", L("hw.m.cell_disconnect"), hideZero: false),
            str("hw.model", BatteryService.hardwareModel(), L("hw.m.machine_model")),
        ])
        if !ident.isEmpty { groups.append(.init(titleKey: "hw.group.identity", rows: ident)) }

        // 寿命统计
        let life = rows([
            int("LifetimeData.TotalOperatingTime", d.totalOperatingMinutes, "min", L("hw.m.total_runtime"), hideZero: true, .questionable, L("hw.n.total_runtime")),
            int("LifetimeData.MaximumTemperature", d.maximumTemperature, "°C", L("hw.m.temp_max")),
            int("LifetimeData.MinimumTemperature", d.minimumTemperature, "°C", L("hw.m.temp_min")),
            dbl("LifetimeData.AverageTemperature", d.averageTemperature, "%.1f", "°C", L("hw.m.temp_avg"), .conditional, L("hw.n.temp_avg")),
            int("LifetimeData.MaximumChargeCurrent", d.maximumChargeCurrent, "mA", L("hw.m.max_charge_current")),
            int("LifetimeData.MaximumDischargeCurrent", d.maximumDischargeCurrent, "mA", L("hw.m.max_discharge_current"), hideZero: true, .verified, L("hw.n.max_discharge")),
            int("LifetimeData.MinimumPackVoltage", d.minimumPackVoltage, "mV", L("hw.m.min_pack_voltage"), hideZero: true, .verified, L("hw.n.min_pack_voltage")),
            int("LifetimeData.MaximumPackVoltage", d.maximumPackVoltage, "mV", L("hw.m.max_pack_voltage")),
            int("LifetimeData.TemperatureSamples", d.temperatureSamples, "", L("hw.m.temp_samples")),
            int("BatteryData.DailyMaxSoc", d.dailyMaxSoc, "%", L("hw.m.daily_max_soc")),
            int("BatteryData.DailyMinSoc", d.dailyMinSoc, "%", L("hw.m.daily_min_soc"), hideZero: false, .conditional, L("hw.n.daily_soc")),
        ])
        if !life.isEmpty { groups.append(.init(titleKey: "hw.group.lifetime", rows: life)) }

        // ── 衍生指标：不是 registry 直接给的，是我们算出来的
        var derived: [HardwareRow] = []
        if let sys = d.systemHealthPercent {
            derived.append(HardwareRow(key: "→ health (system)", value: LNum("%.1f", sys), unit: "%",
                meaning: L("hw.m.health_system"), reliability: .derived, note: L("hw.n.health_system")))
        }
        if let raw = d.rawHealthPercent {
            derived.append(HardwareRow(key: "→ health (raw)", value: LNum("%.1f", raw), unit: "%",
                meaning: L("hw.m.health_raw"), reliability: .derived, note: L("hw.n.health_raw")))
        }
        if let unusable = d.unusableCharge {
            derived.append(HardwareRow(key: "→ Qmax − FCC", value: unusable.formatted(), unit: "mAh",
                meaning: L("hw.m.unusable"), reliability: .derived, note: L("hw.n.unusable")))
        }
        if let per = d.chargeDeficitPerCycle, let total = d.chargeDeficitTotal {
            derived.append(HardwareRow(key: "→ deficit / cycle", value: LNum("%.1f", per), unit: "mAh",
                meaning: L("hw.m.deficit_cycle"), reliability: .derived, note: L("hw.n.deficit_cycle")))
            derived.append(HardwareRow(key: "→ deficit total", value: total.formatted(), unit: "mAh",
                meaning: L("hw.m.deficit_total"), reliability: .derived, note: L("hw.n.deficit_total")))
        }
        if let fresh = d.calibrationAgeCycles {
            derived.append(HardwareRow(key: "→ since last Qmax", value: fresh.formatted(), unit: L("gauge.cycles_unit_bare"),
                meaning: L("hw.m.calib_age"), reliability: .derived, note: L("hw.n.calib_age")))
        }
        if !d.cellVoltages.isEmpty {
            derived.append(HardwareRow(key: "→ pack topology",
                value: "\(d.cellVoltages.count)S1P", unit: "—",
                meaning: L("hw.m.topology"), reliability: .derived, note: L("hw.n.topology")))
        }
        if !derived.isEmpty { groups.append(.init(titleKey: "hw.group.derived", rows: derived)) }

        return groups
    }

}
