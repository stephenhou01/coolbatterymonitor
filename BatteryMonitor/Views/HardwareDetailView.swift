import SwiftUI

// MARK: - 硬件原始数据（折叠，给极客看）
//
// 值为 0 / 空数组 / 空字符串的行整行隐藏，而不是显示一堆「—」。整组全空则整组隐藏
// （比如拔电时充电器组、电池供电时瞬时遥测组）。

struct HardwareRow: Identifiable {
    let id = UUID()
    let key: String          // registry 字段名，原样给极客看
    let value: String
    let unit: String
    let meaning: String      // 人话解释
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
                        .background(Capsule().fill(Color.white.opacity(0.05)))
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
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 2.5)
                                .padding(.horizontal, 6)
                                .background(RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.white.opacity(0.02)))
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

    private var header: some View {
        HStack(spacing: 8) {
            Text(L("hw.field")).frame(width: 190, alignment: .leading)
            Text(L("hw.value")).frame(width: 130, alignment: .leading)
            Text("Unit").frame(width: 56, alignment: .leading)
            Text(L("hw.meaning"))
            Spacer(minLength: 0)
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
        func int(_ k: String, _ v: Int, _ u: String, _ m: String, hideZero: Bool = true) -> HardwareRow? {
            if hideZero && v == 0 { return nil }
            return HardwareRow(key: k, value: v.formatted(), unit: u, meaning: m)
        }
        func dbl(_ k: String, _ v: Double, _ fmt: String, _ u: String, _ m: String) -> HardwareRow? {
            guard abs(v) > 0.0001 else { return nil }
            return HardwareRow(key: k, value: LNum(fmt, v), unit: u, meaning: m)
        }
        func arr(_ k: String, _ v: [Int], _ u: String, _ m: String) -> HardwareRow? {
            guard !v.isEmpty else { return nil }
            return HardwareRow(key: k, value: v.map(String.init).joined(separator: " / "), unit: u, meaning: m)
        }
        func str(_ k: String, _ v: String, _ m: String) -> HardwareRow? {
            guard !v.isEmpty else { return nil }
            return HardwareRow(key: k, value: v, unit: "—", meaning: m)
        }

        // 电芯
        let cells = rows([
            arr("CellVoltage", d.cellVoltages, "mV", cellsMeaning(d)),
            d.cellVoltageDelta.flatMap { int("CellVoltage.delta", $0, "mV", L("insight.factor.balance")) },
            arr("WeightedRa", d.weightedRa, "mΩ", L("insight.factor.resistance")),
            arr("Qmax", d.qmax, "mAh", L("hw.group.capacity")),
            arr("PresentDOD", d.presentDOD, "%", "depth of discharge"),
        ])
        if !cells.isEmpty { groups.append(.init(titleKey: "hw.group.cells", rows: cells)) }

        // 容量与寿命
        let cap = rows([
            int("DesignCapacity", d.designCapacity, "mAh", "factory design capacity"),
            int("AppleRawMaxCapacity", d.appleRawMaxCapacity, "mAh", "current full-charge capacity"),
            int("AppleRawCurrentCapacity", d.appleRawCurrentCapacity, "mAh", "charge available now"),
            int("NominalChargeCapacity", d.nominalChargeCapacity, "mAh", "nominal capacity"),
            int("PackReserve", d.packReserve, "mAh", "reserved capacity"),
            int("CycleCount", d.cycleCount, "", "charge cycles used"),
            int("DesignCycleCount9C", d.designCycleCount, "", "rated cycle life"),
            d.rawHealthPercent.flatMap { dbl("→ health", $0, "%.1f", "%", L("insight.factor.capacity")) },
        ])
        if !cap.isEmpty { groups.append(.init(titleKey: "hw.group.capacity", rows: cap)) }

        // 电气
        let elec = rows([
            int("AppleRawBatteryVoltage", d.packVoltage, "mV", "pack voltage"),
            int("InstantAmperage", d.instantAmperage, "mA", "instantaneous current", hideZero: false),
            int("Amperage", d.smoothedAmperage, "mA", "smoothed current", hideZero: false),
            dbl("VirtualTemperature", d.virtualTemperature, "%.2f", "°C", "with thermal model"),
            dbl("BatteryData.SystemPower", d.systemPowerWatts, "%.2f", "W", "total system power"),
        ])
        if !elec.isEmpty { groups.append(.init(titleKey: "hw.group.electrical", rows: elec)) }

        // 充电器（拔电时整组隐藏）
        let chg = rows([
            int("AdapterDetails.Watts", d.adapterWatts, "W", "rated power"),
            int("AdapterDetails.AdapterVoltage", d.adapterVoltage, "mV", "negotiated voltage"),
            int("AdapterDetails.Current", d.adapterCurrent, "mA", "negotiated current"),
            str("AdapterDetails.Description", d.adapterDescription, "connector type"),
            d.usbHvcMenu.isEmpty ? nil : HardwareRow(
                key: "AdapterDetails.UsbHvcMenu",
                value: d.usbHvcMenu.map { LNum("%.0fV/%.1fA", Double($0.voltage) / 1000, Double($0.current) / 1000) }
                                   .joined(separator: " · "),
                unit: "—", meaning: "PD profiles"),
            int("ChargerData.ChargingVoltage", d.chargingVoltageLimit, "mV", "charge voltage limit"),
            // hideZero 必须为 true：否则拔电时这一行会单独把整个充电器组撑着不隐藏
            int("ChargerData.ChargingCurrent", d.chargingCurrentLimit, "mA", "charge current limit"),
            int("ChargerData.NotChargingReason", d.notChargingReason, "", "bitmask"),
            int("ChargerData.ChargerID", d.chargerID, "", "charger id"),
        ])
        if !chg.isEmpty { groups.append(.init(titleKey: "hw.group.charger", rows: chg)) }

        // 功耗遥测（电池供电时瞬时字段为 0，会自动隐藏）
        let tel = rows([
            int("PowerTelemetryData.SystemLoad", d.systemLoad, "mW", "system load"),
            int("PowerTelemetryData.BatteryPower", d.batteryPower, "mW", "battery power flow", hideZero: false),
            int("PowerTelemetryData.SystemPowerIn", d.systemPowerIn, "mW", "wall input power"),
            int("PowerTelemetryData.SystemVoltageIn", d.systemVoltageIn, "mV", "wall input voltage"),
            int("PowerTelemetryData.SystemCurrentIn", d.systemCurrentIn, "mA", "wall input current"),
            d.adapterEfficiency.flatMap { dbl("→ adapter efficiency", $0, "%.1f", "%", "computed") },
        ])
        if !tel.isEmpty { groups.append(.init(titleKey: "hw.group.telemetry", rows: tel)) }

        // 身份
        let ident = rows([
            str("Serial", d.serialNumber, "battery serial"),
            str("DeviceName", d.gaugeChip, "gas gauge chip"),
            int("GasGaugeFirmwareVersion", d.gaugeFirmwareVersion, "", "gauge firmware"),
            int("BatteryData.ChemID", d.chemistryID, "", "cell chemistry"),
            int("BatteryData.DataFlashWriteCount", d.dataFlashWriteCount, "", "flash writes"),
            int("PermanentFailureStatus", d.permanentFailureStatus, "", "0 = healthy", hideZero: false),
            int("BatteryCellDisconnectCount", d.cellDisconnectCount, "", "cell disconnects", hideZero: false),
            str("hw.model", BatteryService.hardwareModel(), "machine model"),
        ])
        if !ident.isEmpty { groups.append(.init(titleKey: "hw.group.identity", rows: ident)) }

        // 寿命统计
        let life = rows([
            int("LifetimeData.TotalOperatingTime", d.totalOperatingMinutes, "min", "total operating time"),
            int("LifetimeData.MaximumTemperature", d.maximumTemperature, "°C", "all-time high"),
            int("LifetimeData.MinimumTemperature", d.minimumTemperature, "°C", "all-time low"),
            dbl("LifetimeData.AverageTemperature", d.averageTemperature, "%.1f", "°C", "lifetime average"),
            int("LifetimeData.MaximumChargeCurrent", d.maximumChargeCurrent, "mA", "peak charge current"),
            int("LifetimeData.MaximumDischargeCurrent", d.maximumDischargeCurrent, "mA", "peak discharge current"),
            int("LifetimeData.MinimumPackVoltage", d.minimumPackVoltage, "mV", "lowest pack voltage"),
            int("LifetimeData.MaximumPackVoltage", d.maximumPackVoltage, "mV", "highest pack voltage"),
            int("LifetimeData.TemperatureSamples", d.temperatureSamples, "", "temperature samples"),
            int("BatteryData.DailyMaxSoc", d.dailyMaxSoc, "%", "today's high"),
            int("BatteryData.DailyMinSoc", d.dailyMinSoc, "%", "today's low", hideZero: false),
        ])
        if !life.isEmpty { groups.append(.init(titleKey: "hw.group.lifetime", rows: life)) }

        return groups
    }

    private static func cellsMeaning(_ d: BatteryHardwareDetail) -> String {
        d.cellVoltages.isEmpty ? "" : "\(d.cellVoltages.count) cells in series"
    }
}
