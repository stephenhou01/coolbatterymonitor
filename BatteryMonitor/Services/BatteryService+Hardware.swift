import Foundation
import Darwin

// MARK: - IOKit Registry 解析
//
// 字段名和单位都是在真机 dump `ioreg -rn AppleSmartBattery` 后核对过的，不是照
// 文档抄的。所有取值都走 as? + 缺省，任何字段缺失只影响它自己那一行。

extension BatteryService {

    /// 温度单位在不同平台不一致，按量级判断：
    ///   Apple Silicon 报 centi-°C（3079 → 30.79）
    ///   部分 Intel 机型报 deci-°C（307 → 30.7）
    ///   极少数直接报 °C
    static func decodeTemperature(_ raw: Int) -> Double {
        if raw > 1000 { return Double(raw) / 100.0 }
        if raw > 100 { return Double(raw) / 10.0 }
        return Double(raw)
    }

    static func parseHardwareDetail(_ info: [String: Any], fallbackCycleCount: Int) -> BatteryHardwareDetail {
        var d = BatteryHardwareDetail()

        // ── 平台
        d.architecture = currentArchitecture()
        d.chipModel = sysctlString("machdep.cpu.brand_string")
        d.osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        // ── 顶层
        d.cycleCount = info["CycleCount"] as? Int ?? fallbackCycleCount
        d.designCapacity = info["DesignCapacity"] as? Int ?? 0
        d.designCycleCount = info["DesignCycleCount9C"] as? Int ?? 0
        d.nominalChargeCapacity = info["NominalChargeCapacity"] as? Int ?? 0
        d.appleRawMaxCapacity = info["AppleRawMaxCapacity"] as? Int ?? 0
        d.appleRawCurrentCapacity = info["AppleRawCurrentCapacity"] as? Int ?? 0
        d.packReserve = info["PackReserve"] as? Int ?? 0
        d.packVoltage = info["AppleRawBatteryVoltage"] as? Int ?? info["Voltage"] as? Int ?? 0
        d.instantAmperage = info["InstantAmperage"] as? Int ?? 0
        d.smoothedAmperage = info["Amperage"] as? Int ?? 0
        d.serialNumber = info["Serial"] as? String ?? ""
        d.gaugeChip = info["DeviceName"] as? String ?? ""
        d.gaugeFirmwareVersion = info["GasGaugeFirmwareVersion"] as? Int ?? 0
        d.permanentFailureStatus = info["PermanentFailureStatus"] as? Int ?? 0
        d.cellDisconnectCount = info["BatteryCellDisconnectCount"] as? Int ?? 0
        if let vt = info["VirtualTemperature"] as? Int, vt != 0 {
            d.virtualTemperature = decodeTemperature(vt)
        }

        // ── BatteryData 子字典（电芯级 + 寿命统计）
        if let bd = info["BatteryData"] as? [String: Any] {
            d.cellVoltages = bd["CellVoltage"] as? [Int] ?? []
            d.qmax = bd["Qmax"] as? [Int] ?? []
            d.weightedRa = bd["WeightedRa"] as? [Int] ?? []
            d.presentDOD = bd["PresentDOD"] as? [Int] ?? []
            d.chemistryID = bd["ChemID"] as? Int ?? 0
            d.dataFlashWriteCount = bd["DataFlashWriteCount"] as? Int ?? 0
            d.dailyMaxSoc = bd["DailyMaxSoc"] as? Int ?? 0
            d.dailyMinSoc = bd["DailyMinSoc"] as? Int ?? 0
            // SystemPower 直接是 Double（W），比 PowerTelemetry 的 mW 更好用
            d.systemPowerWatts = bd["SystemPower"] as? Double ?? 0

            if let lt = bd["LifetimeData"] as? [String: Any] {
                d.totalOperatingMinutes = lt["TotalOperatingTime"] as? Int ?? 0
                d.temperatureSamples = lt["TemperatureSamples"] as? Int ?? 0
                // AverageTemperature 是 deci-°C（247 → 24.7），与顶层 Temperature 不同
                if let avg = lt["AverageTemperature"] as? Int, avg != 0 {
                    d.averageTemperature = Double(avg) / 10.0
                }
                // Min/MaximumTemperature 是直接 °C（9 / 39），不需要换算
                d.minimumTemperature = lt["MinimumTemperature"] as? Int ?? 0
                d.maximumTemperature = lt["MaximumTemperature"] as? Int ?? 0
                d.maximumChargeCurrent = lt["MaximumChargeCurrent"] as? Int ?? 0
                // 实测已是负 Int（-3302），不需要 UInt64 补码转换
                d.maximumDischargeCurrent = lt["MaximumDischargeCurrent"] as? Int ?? 0
                d.minimumPackVoltage = lt["MinimumPackVoltage"] as? Int ?? 0
                d.maximumPackVoltage = lt["MaximumPackVoltage"] as? Int ?? 0
            }
        }

        // ── AdapterDetails（拔电后只剩 {FamilyCode: 0}，所以全部按缺省处理）
        if let ad = info["AdapterDetails"] as? [String: Any] {
            d.adapterWatts = ad["Watts"] as? Int ?? 0
            d.adapterVoltage = ad["AdapterVoltage"] as? Int ?? 0
            d.adapterCurrent = ad["Current"] as? Int ?? 0
            d.adapterDescription = ad["Description"] as? String ?? ""
            d.adapterIsWireless = ad["IsWireless"] as? Bool ?? false
            if let menu = ad["UsbHvcMenu"] as? [[String: Any]] {
                d.usbHvcMenu = menu.compactMap {
                    guard let v = $0["MaxVoltage"] as? Int, let c = $0["MaxCurrent"] as? Int else { return nil }
                    return BatteryHardwareDetail.PDProfile(voltage: v, current: c)
                }
            }
        }

        // ── ChargerData
        if let cd = info["ChargerData"] as? [String: Any] {
            d.chargingVoltageLimit = cd["ChargingVoltage"] as? Int ?? 0
            d.chargingCurrentLimit = cd["ChargingCurrent"] as? Int ?? 0
            d.notChargingReason = cd["NotChargingReason"] as? Int ?? 0
            d.chargerID = cd["ChargerID"] as? Int ?? 0
        }

        // ── PowerTelemetryData（瞬时字段电池供电时为 0，SystemLoad/BatteryPower 一直有）
        if let pt = info["PowerTelemetryData"] as? [String: Any] {
            d.systemLoad = pt["SystemLoad"] as? Int ?? 0
            d.batteryPower = pt["BatteryPower"] as? Int ?? 0
            d.systemPowerIn = pt["SystemPowerIn"] as? Int ?? 0
            d.systemVoltageIn = pt["SystemVoltageIn"] as? Int ?? 0
            d.systemCurrentIn = pt["SystemCurrentIn"] as? Int ?? 0
            d.adapterEfficiencyLoss = pt["AdapterEfficiencyLoss"] as? Int ?? 0
            d.accumulatedWallEnergy = pt["AccumulatedWallEnergyEstimate"] as? Int ?? 0
        }

        return d
    }

    // MARK: - 平台探测

    static func currentArchitecture() -> BatteryHardwareDetail.ChipArchitecture {
        let brand = sysctlString("machdep.cpu.brand_string")
        if brand.isEmpty { return .unknown }
        return brand.localizedCaseInsensitiveContains("apple") ? .appleSilicon : .intel
    }

    static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "" }
        return String(cString: buf)
    }

    /// 机型标识，如 "Mac16,12"
    static func hardwareModel() -> String { sysctlString("hw.model") }
}
