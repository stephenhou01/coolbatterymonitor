import SwiftUI

// MARK: - 74-row catalog

enum CompleteHardwareMetricCatalog {
    static func build(_ data: BatteryData) -> [CompleteHardwareGroup] {
        let d = data.hardwareDetail
        let spec = data.modelSpecification

        func intText(_ value: Int?, grouped: Bool = false) -> String {
            guard let value else { return "—" }
            return grouped ? value.formatted() : String(value)
        }

        func rawIntText(_ field: String, _ value: Int, grouped: Bool = false) -> String {
            guard d.presentRawFields.contains(field) else { return "—" }
            return grouped ? value.formatted() : String(value)
        }

        func rawDoubleText(_ field: String, _ value: Double, format: String = "%.1f") -> String {
            guard d.presentRawFields.contains(field), value.isFinite else { return "—" }
            return LNum(format, value)
        }

        func rawStringText(_ field: String, _ value: String) -> String {
            guard d.presentRawFields.contains(field) else { return "—" }
            return value.isEmpty ? "\"\"" : value
        }

        func int64Text(_ value: Int64?) -> String {
            value.map { $0.formatted() } ?? "—"
        }

        func doubleText(_ value: Double?, format: String = "%.1f") -> String {
            guard let value, value.isFinite else { return "—" }
            return LNum(format, value)
        }

        func arrayText(_ value: [Int]?) -> String {
            guard let value, !value.isEmpty else { return "—" }
            return value.map(String.init).joined(separator: " / ")
        }

        func rawArrayText(_ field: String, _ value: [Int]) -> String {
            guard d.presentRawFields.contains(field) else { return "—" }
            return value.isEmpty ? "[]" : value.map(String.init).joined(separator: " / ")
        }

        func boolText(_ value: Bool?) -> String {
            guard let value else { return "—" }
            return value ? "true" : "false"
        }

        func timeText(_ value: Int?) -> String {
            guard let value, (1...65_534).contains(value) else { return "—" }
            return value.formatted()
        }

        func text(_ key: String) -> String {
            hardwareText(key)
        }

        let usePrimary = text("hw.usage.primary")
        let useCalculation = text("hw.usage.calculation")
        let useDiagnosis = text("hw.usage.diagnosis")
        let useTable = text("hw.usage.table")
        let useGuarded = text("hw.usage.guarded")
        let useUnused = text("hw.usage.unused")

        func metric(
            _ group: String,
            _ field: String,
            _ value: String,
            _ unit: String,
            _ meaningKey: String,
            reliability: FieldReliability = .verified,
            usage: String = useTable,
            stars: Int = 1,
            noteKey: String? = nil,
            rawFields: [MetricRawField]? = nil,
            formula: String? = nil,
            substitution: String? = nil
        ) -> CompleteHardwareMetric {
            let meaning = text(meaningKey)
            let note = noteKey.map(text) ?? meaning
            // ModelDesignEnergy comes from the built-in specification table, not
            // from a poll, and must not be captioned as a live reading.
            let raw = rawFields ?? [MetricRawField(name: field, value: value, unit: unit,
                                                   updateClass: field == "ModelDesignEnergy" ? .modelSpec : .live)]
            let f = formula ?? "IOKit → \(field)"
            let s = substitution ?? "\(field) → \(value)\(unit.isEmpty ? "" : " \(unit)")"
            return CompleteHardwareMetric(
                id: "\(group).\(field)",
                field: field,
                value: value,
                unit: unit,
                meaning: meaning,
                referenceRange: referenceRange(field: field, data: data),
                reliability: reliability,
                usage: usage,
                valueStars: min(max(stars, 0), 3),
                note: note,
                rawFields: raw,
                formula: f,
                substitution: s,
                // 74 行硬件表全是电量计字段，优先用它自报的发布时刻
                readAt: data.hardwareDetail.gaugeUpdateTime.map {
                    .gauge($0, polledAt: data.lastUpdated,
                           interval: data.hardwareDetail.gaugePublishInterval)
                } ?? .ourRead(data.lastUpdated)
            )
        }

        let modelIdentifier = data.modelIdentifier.isEmpty ? BatteryService.hardwareModel() : data.modelIdentifier
        let designWh = spec?.designEnergyWh
        let currentFullWh = data.currentFullEnergyWh
        let healthSystem = data.systemHealthPercent
        let healthRaw = d.rawHealthPercent
        let unusable = d.unusableCharge
        let usedSinceFull = d.usedSinceFullCapacity
        let permanentChemicalLoss = d.permanentChemicalLoss
        let deficit = d.chargeDeficitTotal

        let capacity = [
            metric("capacity", "DesignCapacity", rawIntText("DesignCapacity", d.designCapacity, grouped: true), "mAh",
                   "hw.m.design_capacity", usage: useCalculation, stars: 2),
            metric("capacity", "ModelDesignEnergy", doubleText(designWh, format: "%.1f"), "Wh",
                   "hw.m.model_design_energy", reliability: .conditional,
                   usage: useCalculation, stars: 3, noteKey: "hw.n.model_design_energy",
                   rawFields: [
                    .init(name: "hw.model", value: modelIdentifier),
                    .init(name: "Apple published model specification", value: doubleText(designWh, format: "%.1f"), unit: "Wh")
                   ], formula: "hw.model → Apple published battery specification",
                   substitution: "\(modelIdentifier) → \(doubleText(designWh, format: "%.1f")) Wh"),
            metric("capacity", "AppleRawMaxCapacity", rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity, grouped: true), "mAh",
                   "hw.m.raw_max", usage: usePrimary, stars: 3,
                   noteKey: "hw.n.raw_max"),
            metric("capacity", "BatteryData.FccComp1 / FccComp2",
                   "\(intText(d.fccComp1)) / \(intText(d.fccComp2))", "mAh",
                   "hw.m.fcc_comp", usage: useGuarded, stars: 1,
                   noteKey: "hw.n.fcc_comp",
                   rawFields: [
                    .init(name: "BatteryData.FccComp1", value: intText(d.fccComp1), unit: "mAh"),
                    .init(name: "BatteryData.FccComp2", value: intText(d.fccComp2), unit: "mAh")
                   ]),
            metric("capacity", "AppleRawCurrentCapacity", rawIntText("AppleRawCurrentCapacity", d.appleRawCurrentCapacity, grouped: true), "mAh",
                   "hw.m.raw_current", usage: useCalculation, stars: 2,
                   noteKey: "hw.n.raw_current"),
            metric("capacity", "CurrentCapacity", intText(d.currentCapacityRaw), "%",
                   "hw.m.current_capacity", usage: usePrimary, stars: 2,
                   noteKey: "hw.n.current_capacity"),
            metric("capacity", "NominalChargeCapacity", rawIntText("NominalChargeCapacity", d.nominalChargeCapacity, grouped: true), "mAh",
                   "hw.m.nominal", usage: useGuarded, stars: 2,
                   noteKey: "hw.n.nominal_relation",
                   rawFields: [
                    .init(name: "NominalChargeCapacity", value: rawIntText("NominalChargeCapacity", d.nominalChargeCapacity), unit: "mAh"),
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "PackReserve", value: rawIntText("PackReserve", d.packReserve), unit: "mAh")
                   ], formula: "NominalChargeCapacity = AppleRawMaxCapacity + PackReserve",
                   substitution: "\(rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity)) + \(rawIntText("PackReserve", d.packReserve)) = \(rawIntText("NominalChargeCapacity", d.nominalChargeCapacity)) mAh"),
            metric("capacity", "PackReserve", rawIntText("PackReserve", d.packReserve), "mAh",
                   "hw.m.reserve", usage: useCalculation, stars: 3,
                   noteKey: "hw.n.reserve"),
            metric("capacity", "MaxCapacity", intText(d.maxCapacityRaw), "% / mAh",
                   "hw.m.max_capacity_raw", reliability: .conditional,
                   usage: useGuarded, stars: 1, noteKey: "hw.n.max_capacity_raw"),
            metric("capacity", "CycleCount", rawIntText("CycleCount", d.cycleCount), "count",
                   "hw.m.cycles", usage: usePrimary, stars: 3),
            metric("capacity", "DesignCycleCount9C", rawIntText("DesignCycleCount9C", d.designCycleCount, grouped: true), "count",
                   "hw.m.design_cycles", usage: useCalculation, stars: 3,
                   noteKey: "hw.n.design_cycles"),
            metric("capacity", "BatteryData.Qmax", rawArrayText("BatteryData.Qmax", d.qmax), "mAh",
                   "hw.m.qmax", usage: useDiagnosis, stars: 2,
                   noteKey: "hw.n.qmax"),
            metric("capacity", "→ current full energy", doubleText(currentFullWh, format: "%.2f"), "Wh",
                   "hw.m.current_full_energy", reliability: .derived,
                   usage: useCalculation, stars: 2, noteKey: "hw.n.current_full_energy",
                   rawFields: [
                    .init(name: "ModelDesignEnergy", value: doubleText(designWh, format: "%.1f"), unit: "Wh"),
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh")
                   ], formula: "currentFullWh = modelDesignWh × AppleRawMaxCapacity ÷ DesignCapacity",
                   substitution: "\(doubleText(designWh, format: "%.1f")) × \(d.appleRawMaxCapacity) ÷ \(d.designCapacity) = \(doubleText(currentFullWh, format: "%.2f")) Wh"),
            metric("capacity", "→ health (system)", doubleText(healthSystem, format: "%.1f"), "%",
                   "hw.m.health_system", reliability: .derived,
                   usage: usePrimary, stars: 2, noteKey: "hw.n.health_system",
                   rawFields: [
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "PackReserve", value: rawIntText("PackReserve", d.packReserve), unit: "mAh"),
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh")
                   ], formula: "health = (FCC + reserve) ÷ (design − reserve) × 100",
                   substitution: "(\(d.appleRawMaxCapacity) + \(d.packReserve)) ÷ (\(d.designCapacity) − \(d.packReserve)) × 100 = \(doubleText(healthSystem, format: "%.1f"))%"),
            metric("capacity", "→ health (raw)", doubleText(healthRaw, format: "%.1f"), "%",
                   "hw.m.health_raw", reliability: .derived,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.health_raw",
                   rawFields: [
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh")
                   ], formula: "rawHealth = AppleRawMaxCapacity ÷ DesignCapacity × 100",
                   substitution: "\(d.appleRawMaxCapacity) ÷ \(d.designCapacity) × 100 = \(doubleText(healthRaw, format: "%.1f"))%"),
            metric("capacity", "→ Qmax − FCC", intText(unusable), "mAh",
                   "hw.m.unusable", reliability: .derived,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.unusable",
                   rawFields: [
                    .init(name: "BatteryData.Qmax.min", value: intText(d.qmax.min()), unit: "mAh"),
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh")
                   ], formula: "unusable = min(Qmax cells) − FCC",
                   substitution: "\(intText(d.qmax.min())) − \(d.appleRawMaxCapacity) = \(intText(unusable)) mAh"),
            metric("capacity", "→ deficit total", intText(deficit), "mAh",
                   "hw.m.deficit_total", reliability: .derived,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.deficit_total",
                   rawFields: [
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh"),
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh")
                   ], formula: "totalDeficit = DesignCapacity − AppleRawMaxCapacity",
                   substitution: "\(d.designCapacity) − \(d.appleRawMaxCapacity) = \(intText(deficit)) mAh"),
            metric("capacity", "→ FCC − current", intText(usedSinceFull), "mAh",
                   "p.used_since_full", reliability: .derived,
                   usage: useCalculation, stars: 3, noteKey: "hw.n.used_since_full",
                   rawFields: [
                    .init(name: "AppleRawMaxCapacity", value: rawIntText("AppleRawMaxCapacity", d.appleRawMaxCapacity), unit: "mAh"),
                    .init(name: "AppleRawCurrentCapacity", value: rawIntText("AppleRawCurrentCapacity", d.appleRawCurrentCapacity), unit: "mAh")
                   ], formula: "usedSinceFull = AppleRawMaxCapacity − AppleRawCurrentCapacity",
                   substitution: "\(d.appleRawMaxCapacity) − \(d.appleRawCurrentCapacity) = \(intText(usedSinceFull)) mAh"),
            metric("capacity", "→ Design − min(Qmax)", intText(permanentChemicalLoss), "mAh",
                   "p.permanent_loss", reliability: .derived,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.permanent_chemical",
                   rawFields: [
                    .init(name: "DesignCapacity", value: rawIntText("DesignCapacity", d.designCapacity), unit: "mAh"),
                    .init(name: "BatteryData.Qmax.min", value: intText(d.learnedChemicalCapacity), unit: "mAh")
                   ], formula: "permanentChemicalLoss = DesignCapacity − min(Qmax cells)",
                   substitution: "\(d.designCapacity) − \(intText(d.learnedChemicalCapacity)) = \(intText(permanentChemicalLoss)) mAh")
        ]

        let dischargeRuntimeValue = data.isOnAC
            ? "—"
            : "\(timeText(d.timeRemainingRaw)) / \(timeText(d.avgTimeToEmpty))"
        let chargeRuntimeValue = data.isCharging ? timeText(d.avgTimeToFull) : "—"
        let runtime = [
            metric("runtime", "TimeRemaining / AvgTimeToEmpty",
                   dischargeRuntimeValue, "min",
                   "hw.m.time_remaining", usage: usePrimary, stars: 3,
                   noteKey: "hw.n.time_remaining",
                   rawFields: [
                    .init(name: "TimeRemaining", value: intText(d.timeRemainingRaw), unit: "min raw"),
                    .init(name: "AvgTimeToEmpty", value: intText(d.avgTimeToEmpty), unit: "min raw")
                   ], formula: "valid(value) when 1 ≤ value ≤ 65,534; otherwise unavailable",
                   substitution: "TimeRemaining \(intText(d.timeRemainingRaw)) / AvgTimeToEmpty \(intText(d.avgTimeToEmpty))"),
            metric("runtime", "AvgTimeToFull", chargeRuntimeValue, "min",
                   "hw.m.time_to_full", reliability: .conditional,
                   usage: useTable, stars: 2, noteKey: "hw.n.time_to_full",
                   rawFields: [.init(name: "AvgTimeToFull", value: intText(d.avgTimeToFull), unit: "min raw")],
                   formula: "valid(value) when charging and value < 65,535",
                   substitution: "AvgTimeToFull = \(intText(d.avgTimeToFull))"),
            metric("runtime", "BatteryInvalidWakeSeconds", intText(d.batteryInvalidWakeSeconds), "s",
                   "hw.m.invalid_wake", usage: useTable, stars: 1,
                   noteKey: "hw.n.invalid_wake")
        ]

        let cells = [
            metric("cells", "BatteryData.CellVoltage", rawArrayText("BatteryData.CellVoltage", d.cellVoltages), "mV",
                   "hw.m.cell_voltage", usage: useDiagnosis, stars: 3,
                   noteKey: "hw.n.cell_voltage"),
            metric("cells", "→ CellVoltage.delta", intText(d.cellVoltageDelta), "mV",
                   "hw.m.cell_delta", reliability: .derived,
                   usage: useDiagnosis, stars: 3,
                   rawFields: [.init(name: "BatteryData.CellVoltage", value: rawArrayText("BatteryData.CellVoltage", d.cellVoltages), unit: "mV")],
                   formula: "delta = max(CellVoltage) − min(CellVoltage)",
                   substitution: "max − min = \(intText(d.cellVoltageDelta)) mV"),
            metric("cells", "BatteryData.PresentDOD", rawArrayText("BatteryData.PresentDOD", d.presentDOD), "%",
                   "hw.m.dod", usage: useTable, stars: 1),
            metric("cells", "BatteryData.CellWom", arrayText(d.cellWom), "—",
                   "hw.m.cell_wom", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.cell_wom"),
            metric("cells", "BatteryCellDisconnectCount", rawIntText("BatteryCellDisconnectCount", d.cellDisconnectCount), "count",
                   "hw.m.cell_disconnect", usage: useDiagnosis, stars: 2,
                   noteKey: "hw.n.cell_disconnect"),
            metric("cells", "PermanentFailureStatus", rawIntText("PermanentFailureStatus", d.permanentFailureStatus), "bitmask",
                   "hw.m.pf_status", usage: useDiagnosis, stars: 3,
                   noteKey: "hw.n.pf_status")
        ]

        let resistance = [
            metric("resistance", "BatteryData.WeightedRa", rawArrayText("BatteryData.WeightedRa", d.weightedRa), "mΩ",
                   "hw.m.weighted_ra", usage: useDiagnosis, stars: 3,
                   noteKey: "hw.n.weighted_ra"),
            metric("resistance", "BatteryData.Ra00–Ra14", arrayText(d.raCurve), "mΩ",
                   "hw.m.ra_curve", reliability: .conditional,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.ra_curve",
                   rawFields: (d.raCurve ?? []).enumerated().map {
                    .init(name: String(format: "BatteryData.Ra%02d", $0.offset), value: String($0.element), unit: "mΩ")
                   }),
            metric("resistance", "BatteryData.ChemicalWeightedRa", intText(d.chemicalWeightedRa), "mΩ",
                   "hw.m.chemical_ra", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.chemical_ra")
        ]

        let virtualTemperatureRaw = d.virtualTemperatureRaw
        let electrical = [
            metric("electrical", "Voltage / AppleRawBatteryVoltage",
                   "\(intText(d.voltageRaw)) / \(intText(d.appleRawBatteryVoltage))", "mV",
                   "hw.m.pack_voltage", usage: useDiagnosis, stars: 2,
                   rawFields: [
                    .init(name: "Voltage", value: intText(d.voltageRaw), unit: "mV"),
                    .init(name: "AppleRawBatteryVoltage", value: intText(d.appleRawBatteryVoltage), unit: "mV")
                   ]),
            metric("electrical", "Amperage", rawIntText("Amperage", d.smoothedAmperage), "mA",
                   "hw.m.smoothed_amperage", usage: usePrimary, stars: 2,
                   noteKey: "hw.n.smoothed_amperage"),
            metric("electrical", "InstantAmperage", rawIntText("InstantAmperage", d.instantAmperage), "mA",
                   "hw.m.instant_amperage", usage: useDiagnosis, stars: 2,
                   noteKey: "hw.n.instant_amperage"),
            metric("electrical", "Temperature", d.temperatureRaw == nil ? "—" : doubleText(data.temperatureCelsius, format: "%.2f"), "°C",
                   "hw.m.temperature", reliability: .conditional,
                   usage: usePrimary, stars: 2, noteKey: "hw.n.temp_unit",
                   rawFields: [.init(name: "Temperature", value: intText(d.temperatureRaw), unit: "raw")],
                   formula: "if raw > 1000: °C = raw ÷ 100; else if raw > 100: °C = raw ÷ 10; else °C = raw",
                   substitution: "\(intText(d.temperatureRaw)) → \(LNum("%.2f", data.temperatureCelsius)) °C"),
            metric("electrical", "VirtualTemperature", virtualTemperatureRaw == nil ? "—" : doubleText(d.virtualTemperature, format: "%.2f"), "°C",
                   "hw.m.virtual_temp", reliability: .conditional,
                   usage: useTable, stars: 1, noteKey: "hw.n.temp_unit",
                   rawFields: [.init(name: "VirtualTemperature", value: intText(virtualTemperatureRaw), unit: "raw")],
                   formula: "decodeTemperature(VirtualTemperature): ÷100, ÷10 or direct by magnitude",
                   substitution: "\(intText(virtualTemperatureRaw)) → \(LNum("%.2f", d.virtualTemperature)) °C"),
            metric("electrical", "BatteryData.SystemPower", rawDoubleText("BatteryData.SystemPower", d.systemPowerWatts, format: "%.2f"), "W",
                   "hw.m.system_power", usage: usePrimary, stars: 3,
                   noteKey: "hw.n.system_power")
        ]

        let voltageInPath = d.presentRawFields.contains("PowerTelemetryData.VoltageIn")
            ? "PowerTelemetryData.VoltageIn" : "PowerTelemetryData.SystemVoltageIn"
        let currentInPath = d.presentRawFields.contains("PowerTelemetryData.CurrentIn")
            ? "PowerTelemetryData.CurrentIn" : "PowerTelemetryData.SystemCurrentIn"
        let inputValue = "\(rawIntText("PowerTelemetryData.SystemPowerIn", d.systemPowerIn)) / \(rawIntText(voltageInPath, d.systemVoltageIn)) / \(rawIntText(currentInPath, d.systemCurrentIn))"
        let telemetry = [
            metric("telemetry", "PowerTelemetryData.SystemLoad", rawIntText("PowerTelemetryData.SystemLoad", d.systemLoad, grouped: true), "mW",
                   "hw.m.system_load", usage: useCalculation, stars: 3,
                   noteKey: "hw.n.system_load"),
            metric("telemetry", "PowerTelemetryData.BatteryPower", rawIntText("PowerTelemetryData.BatteryPower", d.batteryPower, grouped: true), "mW",
                   "hw.m.battery_power", usage: useDiagnosis, stars: 2,
                   noteKey: "hw.n.battery_power"),
            metric("telemetry", "PowerTelemetryData.SystemPowerIn/VoltageIn/CurrentIn", inputValue, "mW / mV / mA",
                   "hw.m.system_input", reliability: .conditional,
                   usage: useTable, stars: 2, noteKey: "hw.n.ac_only",
                   rawFields: [
                    .init(name: "PowerTelemetryData.SystemPowerIn", value: rawIntText("PowerTelemetryData.SystemPowerIn", d.systemPowerIn), unit: "mW"),
                    .init(name: "PowerTelemetryData.VoltageIn / SystemVoltageIn", value: rawIntText(voltageInPath, d.systemVoltageIn), unit: "mV"),
                    .init(name: "PowerTelemetryData.CurrentIn / SystemCurrentIn", value: rawIntText(currentInPath, d.systemCurrentIn), unit: "mA")
                   ]),
            metric("telemetry", "PowerTelemetryData.AdapterEfficiencyLoss", rawIntText("PowerTelemetryData.AdapterEfficiencyLoss", d.adapterEfficiencyLoss), "mW",
                   "hw.m.adapter_efficiency_loss", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.adapter_efficiency_loss"),
            metric("telemetry", "PowerTelemetryData.AccumulatedSystemLoad ÷ Count",
                   doubleText(d.averageTelemetryPowerWatts, format: "%.2f"), "W",
                   "hw.m.accumulated_avg_power", reliability: .derived,
                   usage: useCalculation, stars: 2, noteKey: "hw.n.accumulated_avg_power",
                   rawFields: [
                    .init(name: "PowerTelemetryData.AccumulatedSystemLoad", value: int64Text(d.accumulatedSystemLoad)),
                    .init(name: "PowerTelemetryData.SystemLoadAccumulatorCount", value: int64Text(d.systemLoadAccumulatorCount))
                   ], formula: "averagePower = AccumulatedSystemLoad ÷ Count ÷ 1000",
                   substitution: "\(int64Text(d.accumulatedSystemLoad)) ÷ \(int64Text(d.systemLoadAccumulatorCount)) ÷ 1000 = \(doubleText(d.averageTelemetryPowerWatts, format: "%.2f")) W"),
            metric("telemetry", "PowerTelemetryData.AccumulatedWallEnergyEstimate", rawIntText("PowerTelemetryData.AccumulatedWallEnergyEstimate", d.accumulatedWallEnergy, grouped: true), "raw",
                   "hw.m.wall_energy", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.wall_energy")
        ]

        let lifetime = [
            metric("lifetime", "LifetimeData.MaximumTemperature", rawIntText("LifetimeData.MaximumTemperature", d.maximumTemperature), "°C",
                   "hw.m.temp_max", usage: useDiagnosis, stars: 3),
            metric("lifetime", "LifetimeData.MinimumTemperature", rawIntText("LifetimeData.MinimumTemperature", d.minimumTemperature), "°C",
                   "hw.m.temp_min", usage: useTable, stars: 1),
            metric("lifetime", "LifetimeData.AverageTemperature", rawDoubleText("LifetimeData.AverageTemperature", d.averageTemperature, format: "%.1f"), "°C",
                   "hw.m.temp_avg", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.temp_avg",
                   rawFields: [.init(name: "LifetimeData.AverageTemperature", value: d.presentRawFields.contains("LifetimeData.AverageTemperature") ? String(Int((d.averageTemperature * 10).rounded())) : "—", unit: "0.1°C")],
                   formula: "averageTemperature°C = raw ÷ 10",
                   substitution: "\(Int((d.averageTemperature * 10).rounded())) ÷ 10 = \(doubleText(d.averageTemperature, format: "%.1f")) °C"),
            metric("lifetime", "LifetimeData.TemperatureSamples", rawIntText("LifetimeData.TemperatureSamples", d.temperatureSamples, grouped: true), "count",
                   "hw.m.temp_samples", usage: useDiagnosis, stars: 2),
            metric("lifetime", "LifetimeData.MaximumChargeCurrent", rawIntText("LifetimeData.MaximumChargeCurrent", d.maximumChargeCurrent, grouped: true), "mA",
                   "hw.m.max_charge_current", usage: useDiagnosis, stars: 2),
            metric("lifetime", "LifetimeData.MaximumDischargeCurrent", rawIntText("LifetimeData.MaximumDischargeCurrent", d.maximumDischargeCurrent, grouped: true), "mA",
                   "hw.m.max_discharge_current", usage: useDiagnosis, stars: 2,
                   noteKey: "hw.n.max_discharge"),
            metric("lifetime", "LifetimeData.MinimumPackVoltage", rawIntText("LifetimeData.MinimumPackVoltage", d.minimumPackVoltage), "mV",
                   "hw.m.min_pack_voltage", usage: useDiagnosis, stars: 3,
                   noteKey: "hw.n.min_pack_voltage"),
            metric("lifetime", "LifetimeData.MaximumPackVoltage", rawIntText("LifetimeData.MaximumPackVoltage", d.maximumPackVoltage), "mV",
                   "hw.m.max_pack_voltage", usage: useTable, stars: 1),
            metric("lifetime", "LifetimeData.CycleCountLastQmax", rawIntText("LifetimeData.CycleCountLastQmax", d.cycleCountLastQmax), "cycle",
                   "hw.m.last_qmax_cycle", usage: useDiagnosis, stars: 3,
                   noteKey: "hw.n.last_qmax_cycle"),
            metric("lifetime", "→ since last Qmax", intText(d.calibrationAgeCycles), "cycle",
                   "hw.m.calib_age", reliability: .derived,
                   usage: useDiagnosis, stars: 3, noteKey: "hw.n.calib_age",
                   rawFields: [
                    .init(name: "CycleCount", value: rawIntText("CycleCount", d.cycleCount)),
                    .init(name: "LifetimeData.CycleCountLastQmax", value: rawIntText("LifetimeData.CycleCountLastQmax", d.cycleCountLastQmax))
                   ], formula: "calibrationAge = CycleCount − CycleCountLastQmax",
                   substitution: "\(d.cycleCount) − \(d.cycleCountLastQmax) = \(intText(d.calibrationAgeCycles)) cycles"),
            metric("lifetime", "LifetimeData.TotalOperatingTime", rawIntText("LifetimeData.TotalOperatingTime", d.totalOperatingMinutes, grouped: true), "min",
                   "hw.m.total_runtime", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.total_runtime"),
            metric("lifetime", "BatteryData.DataFlashWriteCount", rawIntText("BatteryData.DataFlashWriteCount", d.dataFlashWriteCount, grouped: true), "count",
                   "hw.m.flash_writes", usage: useTable, stars: 1),
            metric("lifetime", "BatteryData.QmaxDisqualificationReason", intText(d.qmaxDisqualificationReason), "code",
                   "hw.m.qmax_disqualification", usage: useTable, stars: 3,
                   noteKey: "hw.n.qmax_disqualification"),
            metric("lifetime", "BatteryData.DailyMaxSoc / DailyMinSoc",
                   "\(rawIntText("BatteryData.DailyMaxSoc", d.dailyMaxSoc)) / \(rawIntText("BatteryData.DailyMinSoc", d.dailyMinSoc))", "%",
                   "hw.m.daily_soc_pair", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.daily_soc",
                   rawFields: [
                    .init(name: "BatteryData.DailyMaxSoc", value: rawIntText("BatteryData.DailyMaxSoc", d.dailyMaxSoc), unit: "%"),
                    .init(name: "BatteryData.DailyMinSoc", value: rawIntText("BatteryData.DailyMinSoc", d.dailyMinSoc), unit: "%")
                   ])
        ]

        let adapterValue: (String, Int) -> String = { field, value in rawIntText(field, value) }
        let adapterWattsPath = d.presentRawFields.contains("AdapterDetails.Watts")
            ? "AdapterDetails.Watts" : "AdapterDetails.AdapterWatts"
        let pdMenu = !d.presentRawFields.contains("AdapterDetails.UsbHvcMenu") ? "—" : d.usbHvcMenu.isEmpty ? "[]" : d.usbHvcMenu.map {
            "\(LNum("%.1f", Double($0.voltage) / 1000))V/\(LNum("%.1f", Double($0.current) / 1000))A"
        }.joined(separator: " · ")
        let carrier = d.carrierMode
        let carrierValue = carrier.map {
            "\(intText($0.highVoltage)) / \(intText($0.lowVoltage)) / \(intText($0.status))"
        } ?? "—"
        let portCycles = d.portControllers.isEmpty ? "—" : d.portControllers.map {
            "C\($0.index + 1) \(intText($0.attachCount))/\(intText($0.detachCount))"
        }.joined(separator: " · ")
        let portFailures = d.portControllers.isEmpty ? "—" : d.portControllers.map {
            "C\($0.index + 1) \(intText($0.capabilityMismatch))/\(intText($0.electionFailReason))"
        }.joined(separator: " · ")

        let charger = [
            metric("charger", "AdapterDetails.Watts", adapterValue(adapterWattsPath, d.adapterWatts), "W",
                   "hw.m.adapter_watts", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.ac_only"),
            metric("charger", "AdapterDetails.AdapterVoltage / Current",
                   "\(adapterValue("AdapterDetails.AdapterVoltage", d.adapterVoltage)) / \(adapterValue("AdapterDetails.Current", d.adapterCurrent))", "mV / mA",
                   "hw.m.adapter_contract", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.ac_only",
                   rawFields: [
                    .init(name: "AdapterDetails.AdapterVoltage", value: adapterValue("AdapterDetails.AdapterVoltage", d.adapterVoltage), unit: "mV"),
                    .init(name: "AdapterDetails.Current", value: adapterValue("AdapterDetails.Current", d.adapterCurrent), unit: "mA")
                   ]),
            metric("charger", "AdapterDetails.UsbHvcMenu", pdMenu, "raw",
                   "hw.m.adapter_menu", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.adapter_menu"),
            metric("charger", "AdapterDetails.Description", rawStringText("AdapterDetails.Description", d.adapterDescription), "string",
                   "hw.m.adapter_description", reliability: .conditional,
                   usage: useTable, stars: 1, noteKey: "hw.n.ac_only"),
            metric("charger", "ChargerData.ChargingVoltage / ChargingCurrent",
                   "\(rawIntText("ChargerData.ChargingVoltage", d.chargingVoltageLimit)) / \(rawIntText("ChargerData.ChargingCurrent", d.chargingCurrentLimit))", "mV / mA",
                   "hw.m.charge_limits", reliability: .conditional,
                   usage: useDiagnosis, stars: 2, noteKey: "hw.n.charge_i_limit",
                   rawFields: [
                    .init(name: "ChargerData.ChargingVoltage", value: rawIntText("ChargerData.ChargingVoltage", d.chargingVoltageLimit), unit: "mV"),
                    .init(name: "ChargerData.ChargingCurrent", value: rawIntText("ChargerData.ChargingCurrent", d.chargingCurrentLimit), unit: "mA")
                   ]),
            metric("charger", "ChargerData.NotChargingReason", rawIntText("ChargerData.NotChargingReason", d.notChargingReason), "bitmask",
                   "hw.m.not_charging_reason", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.not_charging_reason"),
            metric("charger", "CarrierMode.CarrierModeHighVoltage/LowVoltage/Status", carrierValue, "mV / mV / code",
                   "hw.m.carrier_mode", usage: useTable, stars: 2,
                   noteKey: "hw.n.carrier_mode",
                   rawFields: [
                    .init(name: "CarrierMode.CarrierModeHighVoltage", value: intText(carrier?.highVoltage), unit: "mV"),
                    .init(name: "CarrierMode.CarrierModeLowVoltage", value: intText(carrier?.lowVoltage), unit: "mV"),
                    .init(name: "CarrierMode.CarrierModeStatus", value: intText(carrier?.status))
                   ]),
            metric("charger", "PortControllerInfo[].AttachCount/DetachCount", portCycles, "count",
                   "hw.m.port_cycles", usage: useTable, stars: 2,
                   noteKey: "hw.n.port_cycles",
                   rawFields: d.portControllers.flatMap { port in [
                    .init(name: "PortControllerInfo[\(port.index)].PortControllerAttachCount", value: intText(port.attachCount)),
                    .init(name: "PortControllerInfo[\(port.index)].PortControllerDetachCount", value: intText(port.detachCount))
                   ] }),
            metric("charger", "PortControllerInfo[].CapMismatch / ElectionFailReason", portFailures, "count / code",
                   "hw.m.port_failures", usage: useTable, stars: 3,
                   noteKey: "hw.n.port_failures",
                   rawFields: d.portControllers.flatMap { port in [
                    .init(name: "PortControllerInfo[\(port.index)].PortControllerCapMismatch", value: intText(port.capabilityMismatch)),
                    .init(name: "PortControllerInfo[\(port.index)].PortControllerElectionFailReason", value: intText(port.electionFailReason))
                   ] })
        ]

        let manufactureValue = manufactureDisplay(d.manufactureDateRaw)
        let identity = [
            metric("identity", "Serial", rawStringText("Serial", d.serialNumber), "string",
                   "hw.m.serial", usage: useDiagnosis, stars: 1,
                   noteKey: "hw.n.serial"),
            metric("identity", "DeviceName", rawStringText("DeviceName", d.gaugeChip), "string",
                   "hw.m.gauge_chip", usage: useDiagnosis, stars: 2,
                   noteKey: "hw.n.gauge_chip"),
            metric("identity", "BatteryData.ChemID / AlgoChemID",
                   "\(rawIntText("BatteryData.ChemID", d.chemistryID)) / \(intText(d.algorithmChemistryID))", "code",
                   "hw.m.chem_ids", usage: useTable, stars: 1,
                   rawFields: [
                    .init(name: "BatteryData.ChemID", value: rawIntText("BatteryData.ChemID", d.chemistryID)),
                    .init(name: "BatteryData.AlgoChemID", value: intText(d.algorithmChemistryID))
                   ]),
            metric("identity", "BatteryData.ManufactureDate", manufactureValue, "raw / ASCII",
                   "hw.m.manufacture_batch", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.manufacture_batch",
                   rawFields: [.init(name: "BatteryData.ManufactureDate", value: intText(d.manufactureDateRaw))],
                   formula: "integer → hexadecimal bytes → printable ASCII",
                   substitution: manufactureValue),
            metric("identity", "BatteryData.DateOfFirstUse", intText(d.dateOfFirstUseRaw), "raw",
                   "hw.m.first_use", reliability: .questionable,
                   usage: useUnused, stars: 0, noteKey: "hw.n.first_use"),
            metric("identity", "GasGaugeFirmwareVersion", rawIntText("GasGaugeFirmwareVersion", d.gaugeFirmwareVersion), "version",
                   "hw.m.gauge_fw", usage: useTable, stars: 1),
            metric("identity", "BatteryInstalled / built-in",
                   "\(boolText(d.batteryInstalled)) / \(boolText(d.isBuiltIn))", "bool",
                   "hw.m.installed", usage: useTable, stars: 1,
                   rawFields: [
                    .init(name: "BatteryInstalled", value: boolText(d.batteryInstalled)),
                    .init(name: "built-in", value: boolText(d.isBuiltIn))
                   ]),
            metric("identity", "hw.model", modelIdentifier.isEmpty ? "—" : modelIdentifier, "identifier",
                   "hw.m.machine_model", usage: useCalculation, stars: 2)
        ]

        return [
            group("capacity", "hw.group.capacity", "p.hw_group_capacity", capacity),
            group("runtime", "hw.group.runtime", "p.hw_group_runtime", runtime),
            group("cells", "hw.group.cells", "p.hw_group_cells", cells),
            group("resistance", "hw.group.resistance", "p.hw_group_resistance", resistance),
            group("electrical", "hw.group.electrical", "p.hw_group_electrical", electrical),
            group("telemetry", "hw.group.telemetry", "p.hw_group_telemetry", telemetry),
            group("lifetime", "hw.group.lifetime", "p.hw_group_lifetime", lifetime),
            group("charger", "hw.group.charger", "p.hw_group_charger", charger),
            group("identity", "hw.group.identity", "p.hw_group_identity", identity)
        ]
    }

    private static func group(
        _ id: String,
        _ titleKey: String,
        _ summaryKey: String,
        _ metrics: [CompleteHardwareMetric]
    ) -> CompleteHardwareGroup {
        CompleteHardwareGroup(
            id: id,
            title: hardwareText(titleKey),
            summary: hardwareText(summaryKey),
            metrics: metrics
        )
    }

    private static func referenceRange(field: String, data: BatteryData) -> String {
        let d = data.hardwareDetail
        let noRange = hardwareText("p.no_fixed_range")
        let trend = hardwareText("p.counter_range")
        let identifier = hardwareText("p.id_no_range")

        switch field {
        case "→ CellVoltage.delta": return "0–20 mV"
        case "BatteryData.WeightedRa": return hardwareText("hw.range.weighted_ra")
        case "BatteryData.ChemicalWeightedRa": return "0 = N/A · \(noRange)"
        case "BatteryData.PresentDOD", "CurrentCapacity", "BatteryData.DailyMaxSoc / DailyMinSoc": return "0–100 %"
        case "AppleRawMaxCapacity", "BatteryData.FccComp1 / FccComp2":
            return d.designCapacity > 0
                ? hardwareText("hw.range.compare_design")
                    .replacingOccurrences(of: "{value}", with: d.designCapacity.formatted())
                : noRange
        case "AppleRawCurrentCapacity":
            return d.designCapacity > 0
                ? hardwareText("hw.range.current_capacity")
                    .replacingOccurrences(of: "{value}", with: d.designCapacity.formatted())
                : noRange
        case "NominalChargeCapacity": return hardwareText("hw.range.nominal_relation")
        case "TimeRemaining / AvgTimeToEmpty", "AvgTimeToFull": return hardwareText("hw.range.time_valid")
        case "BatteryInvalidWakeSeconds": return "0+ s · \(trend)"
        case "CycleCount": return d.designCycleCount > 0
            ? hardwareText("hw.range.cycle_rated")
                .replacingOccurrences(of: "{value}", with: d.designCycleCount.formatted())
            : trend
        case "DesignCycleCount9C": return d.designCycleCount > 0
            ? hardwareText("hw.range.design_cycle_rated")
                .replacingOccurrences(of: "{value}", with: d.designCycleCount.formatted())
            : noRange
        case "MaxCapacity":
            return d.architecture == .appleSilicon
                ? hardwareText("hw.range.max_percent")
                : hardwareText("hw.range.max_platform")
        case "→ health (system)", "→ health (raw)": return "80–100 %"
        case "Temperature", "VirtualTemperature": return hardwareText("hw.range.temperature")
        case "BatteryData.SystemPower":
            if let baseline = d.averageTelemetryPowerWatts {
                return hardwareText("hw.range.power_baseline")
                    .replacingOccurrences(of: "{value}", with: LNum("%.1f", baseline))
            }
            return noRange
        case "LifetimeData.MinimumTemperature": return hardwareText("hw.range.lifetime_min")
        case "LifetimeData.MaximumTemperature": return hardwareText("hw.range.lifetime_max")
        case "LifetimeData.AverageTemperature": return hardwareText("hw.range.lifetime_avg")
        case "PermanentFailureStatus", "BatteryCellDisconnectCount": return hardwareText("hw.range.fault_zero")
        case "BatteryData.QmaxDisqualificationReason": return hardwareText("hw.range.qmax_valid")
        case "PortControllerInfo[].CapMismatch / ElectionFailReason": return hardwareText("hw.range.port_zero")
        case "LifetimeData.MinimumPackVoltage", "LifetimeData.MaximumPackVoltage", "Voltage / AppleRawBatteryVoltage":
            if d.minimumPackVoltage > 0, d.maximumPackVoltage > 0 {
                return "\(d.minimumPackVoltage)–\(d.maximumPackVoltage) mV"
            }
            return noRange
        case "DesignCapacity", "ModelDesignEnergy": return hardwareText("p.rated_value")
        case "BatteryData.Qmax", "→ current full energy", "→ Qmax − FCC", "→ Design − min(Qmax)": return noRange
        default:
            if field.contains("Serial") || field.contains("DeviceName") || field.contains("Firmware")
                || field.contains("ChemID") || field.contains("ManufactureDate")
                || field.contains("DateOfFirstUse") || field.contains("installed")
                || field.contains("hw.model") || field.contains("topology")
                || field.contains("Reason") || field.contains("Status")
                || field.contains("Description") {
                return identifier
            }
            if field.contains("Count") || field.contains("Samples")
                || field.contains("OperatingTime") || field.contains("FlashWrite")
                || field.contains("since last") || field.contains("deficit") {
                return trend
            }
            return noRange
        }
    }

    private static func manufactureDisplay(_ raw: Int?) -> String {
        guard let raw else { return "—" }
        let hex = String(raw, radix: 16)
        let padded = hex.count.isMultiple(of: 2) ? hex : "0" + hex
        var bytes: [UInt8] = []
        var index = padded.startIndex
        while index < padded.endIndex {
            let end = padded.index(index, offsetBy: 2)
            guard let byte = UInt8(padded[index..<end], radix: 16) else { return String(raw) }
            bytes.append(byte)
            index = end
        }
        guard let ascii = String(bytes: bytes, encoding: .ascii),
              ascii.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) else {
            return String(raw)
        }
        return "\(raw) / ASCII \(ascii)"
    }
}
