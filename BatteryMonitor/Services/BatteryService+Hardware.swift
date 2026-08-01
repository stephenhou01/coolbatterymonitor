import Foundation
import Darwin

// MARK: - IOKit Registry 解析
//
// 字段名和单位都是在真机 dump `ioreg -rn AppleSmartBattery` 后核对过的，不是照
// 文档抄的。所有取值都走 as? + 缺省，任何字段缺失只影响它自己那一行。

extension BatteryService {

    /// IOKit plist 数字在不同调用路径下可能桥接成 Int 或 NSNumber。
    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func integer64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

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

        // Preserve field presence separately from numeric fallbacks. IOKit uses
        // real zeroes for healthy status flags and inactive AC telemetry, while
        // a missing key means “not returned”; the evidence UI must not conflate
        // those two states.
        d.presentRawFields.formUnion(info.keys)

        // ── 平台
        d.architecture = currentArchitecture()
        d.chipModel = sysctlString("machdep.cpu.brand_string")
        d.osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        // ── 顶层
        d.cycleCount = integer(info["CycleCount"]) ?? fallbackCycleCount
        d.designCapacity = integer(info["DesignCapacity"]) ?? 0
        d.designCycleCount = integer(info["DesignCycleCount9C"]) ?? 0
        d.nominalChargeCapacity = integer(info["NominalChargeCapacity"]) ?? 0
        d.appleRawMaxCapacity = integer(info["AppleRawMaxCapacity"]) ?? 0
        d.appleRawCurrentCapacity = integer(info["AppleRawCurrentCapacity"]) ?? 0
        d.packReserve = integer(info["PackReserve"]) ?? 0
        d.currentCapacityRaw = integer(info["CurrentCapacity"])
        d.maxCapacityRaw = integer(info["MaxCapacity"])
        d.timeRemainingRaw = integer(info["TimeRemaining"])
        d.avgTimeToEmpty = integer(info["AvgTimeToEmpty"])
        d.avgTimeToFull = integer(info["AvgTimeToFull"])
        d.batteryInvalidWakeSeconds = integer(info["BatteryInvalidWakeSeconds"])
        d.voltageRaw = integer(info["Voltage"])
        d.appleRawBatteryVoltage = integer(info["AppleRawBatteryVoltage"])
        d.packVoltage = d.appleRawBatteryVoltage ?? d.voltageRaw ?? 0
        d.temperatureRaw = integer(info["Temperature"])
        d.instantAmperage = integer(info["InstantAmperage"]) ?? 0
        d.smoothedAmperage = integer(info["Amperage"]) ?? 0
        d.serialNumber = info["Serial"] as? String ?? ""
        d.gaugeChip = info["DeviceName"] as? String ?? ""
        d.gaugeFirmwareVersion = integer(info["GasGaugeFirmwareVersion"]) ?? 0
        d.permanentFailureStatus = integer(info["PermanentFailureStatus"]) ?? 0
        d.cellDisconnectCount = integer(info["BatteryCellDisconnectCount"]) ?? 0
        d.batteryInstalled = boolean(info["BatteryInstalled"])
        d.isBuiltIn = boolean(info["built-in"])
        d.virtualTemperatureRaw = integer(info["VirtualTemperature"])
        if let vt = d.virtualTemperatureRaw, vt != 0 {
            d.virtualTemperature = decodeTemperature(vt)
        }

        // ── BatteryData 子字典（电芯级 + 寿命统计）
        if let bd = info["BatteryData"] as? [String: Any] {
            d.presentRawFields.formUnion(bd.keys.map { "BatteryData.\($0)" })
            d.cellVoltages = bd["CellVoltage"] as? [Int] ?? []
            d.qmax = bd["Qmax"] as? [Int] ?? []
            d.weightedRa = bd["WeightedRa"] as? [Int] ?? []
            d.presentDOD = bd["PresentDOD"] as? [Int] ?? []
            d.cellWom = bd["CellWom"] as? [Int]
            let ra = (0..<15).compactMap { integer(bd[String(format: "Ra%02d", $0)]) }
            d.raCurve = ra.count == 15 ? ra : nil
            d.chemicalWeightedRa = integer(bd["ChemicalWeightedRa"])
            d.fccComp1 = integer(bd["FccComp1"])
            d.fccComp2 = integer(bd["FccComp2"])
            d.chemistryID = integer(bd["ChemID"]) ?? 0
            d.algorithmChemistryID = integer(bd["AlgoChemID"])
            d.manufactureDateRaw = integer(bd["ManufactureDate"])
            d.dateOfFirstUseRaw = integer(bd["DateOfFirstUse"])
            d.dataFlashWriteCount = integer(bd["DataFlashWriteCount"]) ?? 0
            d.qmaxDisqualificationReason = integer(bd["QmaxDisqualificationReason"])
            d.dailyMaxSoc = integer(bd["DailyMaxSoc"]) ?? 0
            d.dailyMinSoc = integer(bd["DailyMinSoc"]) ?? 0
            // SystemPower 直接是 Double（W），比 PowerTelemetry 的 mW 更好用
            if let power = bd["SystemPower"] as? Double {
                d.systemPowerWatts = power
            } else if let power = bd["SystemPower"] as? NSNumber {
                d.systemPowerWatts = power.doubleValue
            }

            if let lt = bd["LifetimeData"] as? [String: Any] {
                d.presentRawFields.formUnion(lt.keys.map { "LifetimeData.\($0)" })
                d.totalOperatingMinutes = integer(lt["TotalOperatingTime"]) ?? 0
                d.temperatureSamples = integer(lt["TemperatureSamples"]) ?? 0
                // AverageTemperature 是 deci-°C（247 → 24.7），与顶层 Temperature 不同
                if let avg = integer(lt["AverageTemperature"]), avg != 0 {
                    d.averageTemperature = Double(avg) / 10.0
                }
                // Min/MaximumTemperature 是直接 °C（9 / 39），不需要换算
                d.minimumTemperature = integer(lt["MinimumTemperature"]) ?? 0
                d.maximumTemperature = integer(lt["MaximumTemperature"]) ?? 0
                d.maximumChargeCurrent = integer(lt["MaximumChargeCurrent"]) ?? 0
                // 实测已是负 Int（-3302），不需要 UInt64 补码转换
                d.maximumDischargeCurrent = integer(lt["MaximumDischargeCurrent"]) ?? 0
                d.minimumPackVoltage = integer(lt["MinimumPackVoltage"]) ?? 0
                d.maximumPackVoltage = integer(lt["MaximumPackVoltage"]) ?? 0
                d.cycleCountLastQmax = integer(lt["CycleCountLastQmax"]) ?? 0
            }
        }

        // ── AdapterDetails（拔电后只剩 {FamilyCode: 0}，所以全部按缺省处理）
        if let ad = info["AdapterDetails"] as? [String: Any] {
            d.presentRawFields.formUnion(ad.keys.map { "AdapterDetails.\($0)" })
            d.adapterWatts = integer(ad["Watts"]) ?? 0
            d.adapterVoltage = integer(ad["AdapterVoltage"]) ?? 0
            d.adapterCurrent = integer(ad["Current"]) ?? 0
            d.adapterDescription = ad["Description"] as? String ?? ""
            d.adapterIsWireless = ad["IsWireless"] as? Bool ?? false
            if let menu = ad["UsbHvcMenu"] as? [[String: Any]] {
                d.usbHvcMenu = menu.compactMap {
                    guard let v = integer($0["MaxVoltage"]), let c = integer($0["MaxCurrent"]) else { return nil }
                    return BatteryHardwareDetail.PDProfile(voltage: v, current: c)
                }
            }
        }

        // ── ChargerData
        if let cd = info["ChargerData"] as? [String: Any] {
            d.presentRawFields.formUnion(cd.keys.map { "ChargerData.\($0)" })
            d.chargingVoltageLimit = integer(cd["ChargingVoltage"]) ?? 0
            d.chargingCurrentLimit = integer(cd["ChargingCurrent"]) ?? 0
            d.notChargingReason = integer(cd["NotChargingReason"]) ?? 0
            d.chargerID = integer(cd["ChargerID"]) ?? 0
        }

        // ── CarrierMode：运输/保护模式的限压阈值与状态
        if let cm = info["CarrierMode"] as? [String: Any] {
            d.presentRawFields.formUnion(cm.keys.map { "CarrierMode.\($0)" })
            d.carrierMode = BatteryCarrierModeDetail(
                highVoltage: integer(cm["CarrierModeHighVoltage"]),
                lowVoltage: integer(cm["CarrierModeLowVoltage"]),
                status: integer(cm["CarrierModeStatus"])
            )
        }

        // ── USB-C / MagSafe 端口控制器；数组顺序不推断物理左右位置
        if let ports = info["PortControllerInfo"] as? [[String: Any]] {
            for port in ports {
                d.presentRawFields.formUnion(port.keys.map { "PortControllerInfo[].\($0)" })
            }
            d.portControllers = ports.enumerated().map { index, port in
                BatteryPortControllerDetail(
                    index: index,
                    attachCount: integer(port["PortControllerAttachCount"]),
                    detachCount: integer(port["PortControllerDetachCount"]),
                    capabilityMismatch: integer(port["PortControllerCapMismatch"]),
                    electionFailReason: integer(port["PortControllerElectionFailReason"])
                )
            }
        }

        // ── PowerTelemetryData（瞬时字段电池供电时为 0，SystemLoad/BatteryPower 一直有）
        if let pt = info["PowerTelemetryData"] as? [String: Any] {
            d.presentRawFields.formUnion(pt.keys.map { "PowerTelemetryData.\($0)" })
            d.systemLoad = integer(pt["SystemLoad"]) ?? 0
            d.batteryPower = integer(pt["BatteryPower"]) ?? 0
            d.systemPowerIn = integer(pt["SystemPowerIn"]) ?? 0
            // 真机字段是 VoltageIn / CurrentIn；旧名字只作兼容回退。
            d.systemVoltageIn = integer(pt["VoltageIn"])
                ?? integer(pt["SystemVoltageIn"])
                ?? 0
            d.systemCurrentIn = integer(pt["CurrentIn"])
                ?? integer(pt["SystemCurrentIn"])
                ?? 0
            d.adapterEfficiencyLoss = integer(pt["AdapterEfficiencyLoss"]) ?? 0
            d.accumulatedSystemLoad = integer64(pt["AccumulatedSystemLoad"])
            d.systemLoadAccumulatorCount = integer64(pt["SystemLoadAccumulatorCount"])
            d.accumulatedWallEnergy = integer(pt["AccumulatedWallEnergyEstimate"]) ?? 0
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
