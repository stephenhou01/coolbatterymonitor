#!/usr/bin/env python3
"""生成 BatteryMonitor 产品原型定稿 HTML。

两个原则：
  1. 数据取自真机 ioreg，不编数字
  2. 译文从 Localization/Sources 生成到 Languages —— 与 app 用同一份，不另写一套
"""
import plistlib, subprocess, json, os, glob, re
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["zh-Hans", "en", "ja", "de", "fr", "ko", "zh-Hant", "es", "it", "pt"]

# ── 真机数据 ────────────────────────────────────────────────
raw = subprocess.run(['ioreg', '-rn', 'AppleSmartBattery', '-a'], capture_output=True).stdout
D = plistlib.loads(raw); D = D[0] if isinstance(D, list) else D
BD, PT = D['BatteryData'], D['PowerTelemetryData']
LT = BD['LifetimeData']
DATA_MODEL = subprocess.run(['sysctl','-n','hw.model'],capture_output=True,text=True).stdout.strip()

# 系统只返回 mAh；Wh 使用“系统机型标识 → Apple 该机型额定规格”的本地映射。
# 不能用充满瞬间的高电压直接乘 mAh，那会高估整段放电可用能量。
MODEL_ENERGY_SPECS = {
    "Mac16,12": {
        "name": "MacBook Air (13-inch, M4, 2025)",
        "designWh": 53.8,
        "webHours": 15,
        "videoHours": 18,
        "testCpuCores": 10,
        "testGpuCores": 8,
        "testMemoryGB": 16,
        "testStorageGB": 256,
        "source": "Apple Support 122209",
    },
}
MODEL_ENERGY_SPEC = MODEL_ENERGY_SPECS.get(DATA_MODEL)

def system_profile(data_type):
    try:
        payload = subprocess.run(
            ['system_profiler', data_type, '-json'], capture_output=True, text=True, timeout=12
        ).stdout
        return json.loads(payload).get(data_type, [])
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []

def nested_value(value, key):
    if isinstance(value, dict):
        if key in value:
            return value[key]
        for child in value.values():
            found = nested_value(child, key)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = nested_value(child, key)
            if found is not None:
                return found
    return None

HW_PROFILE = (system_profile('SPHardwareDataType') or [{}])[0]
DISPLAY_PROFILE = system_profile('SPDisplaysDataType')
SYSTEM_CHIP = HW_PROFILE.get('chip_type', 'Apple Silicon')
SYSTEM_CPU_CORES = int(re.search(r'proc (\d+)', HW_PROFILE.get('number_processors', ''))[1]) if re.search(r'proc (\d+)', HW_PROFILE.get('number_processors', '')) else None
SYSTEM_GPU_CORES = int(nested_value(DISPLAY_PROFILE, 'sppci_cores') or 0) or None
SYSTEM_MEMORY = HW_PROFILE.get('physical_memory', '—')

RA = [BD[f"Ra{i:02d}"] for i in range(15)]
CELLS = BD['CellVoltage']
QMAX = BD['Qmax']
design, fcc = D['DesignCapacity'], D['AppleRawMaxCapacity']
cur, reserve = D['AppleRawCurrentCapacity'], D['PackReserve']
cyc, dcyc = D['CycleCount'], D['DesignCycleCount9C']
health_sys = (fcc + reserve) / (design - reserve) * 100
health_raw = fcc / design * 100
unusable = min(QMAX) - fcc
aged = design - min(QMAX)
deficit = design - fcc
deficit_pc = deficit / cyc
calib = cyc - LT['CycleCountLastQmax']
onAC = D.get('ExternalConnected', False)
pmset_text = subprocess.run(['pmset', '-g', 'batt'], capture_output=True, text=True).stdout
pm_soc_match = re.search(r'\b(\d+)%', pmset_text)
soc_ui = int(pm_soc_match.group(1)) if pm_soc_match else D.get('CurrentCapacity', 0)
pm_time_match = re.search(r'\b(\d+):(\d+)\s+remaining\b', pmset_text)
ate = D.get('AvgTimeToEmpty', 0)
if not onAC and pm_time_match:
    ate = int(pm_time_match.group(1)) * 60 + int(pm_time_match.group(2))
amp = D.get('Amperage', 0)
volt = D.get('Voltage', 0) / 1000
watts = BD.get('SystemPower', 0) or abs(amp) * volt / 1000
design_wh = MODEL_ENERGY_SPEC['designWh'] if MODEL_ENERGY_SPEC else None
if design_wh:
    current_full_wh = design_wh * fcc / design
    remaining_wh = design_wh * max(0, min(cur, fcc)) / design
    energy_source = "apple-model-spec"
else:
    # 未收录机型只提供近似值，并在数据中明确标记来源。
    current_full_wh = fcc * volt / 1000
    remaining_wh = max(0, min(cur, fcc)) * volt / 1000
    energy_source = "instant-voltage-fallback"
unplug_estimate = round(remaining_wh / watts * 60) if watts > 0.5 else 0
soc_raw = BD.get('StateOfCharge', 0)
temp = D.get('Temperature', 0) / 100
avg_w = PT['AccumulatedSystemLoad'] / PT['SystemLoadAccumulatorCount'] / 1000
snapshot_at = datetime.now().astimezone().strftime("%H:%M:%S")
snapshot_ms = int(datetime.now().timestamp() * 1000)

# 原型只保存系统直接给出的剩余时间，不用功率或电量反推。
# 反复运行生成器时沿用上一次 HTML 内的真实采样，模拟正式 App 的持久化历史。
dst = f"{ROOT}/Prototype/battery-final.html"
remaining_history = []
if os.path.exists(dst):
    try:
        previous_html = open(dst, encoding='utf-8').read()
        previous_match = re.search(r'^const D = (\{.*\});$', previous_html, re.MULTILINE)
        if previous_match:
            previous_data = json.loads(previous_match.group(1))
            remaining_history = previous_data.get('remainingHistory', [])
    except (OSError, ValueError, TypeError):
        remaining_history = []
if not onAC and 0 < ate < 60000:
    remaining_history.append({"t": snapshot_ms, "minutes": ate})
remaining_history = remaining_history[-96:]

# ── 译文：从 app 的语言包里取 ────────────────────────────────
packs = {}
for lc in LANGS:
    p = f"{ROOT}/Localization/Languages/{lc}.json"
    packs[lc] = json.load(open(p, encoding='utf-8'))

# 原型和 App 读取同一份生成语言包；页面化编辑源位于 Localization/Sources/。
# 原型直接装入完整 key 集，缺失译文逐项回落英文，不再维护第二份 EXTRA。
I18N = {}
for lc in LANGS:
    s = packs[lc]['strings']; en = packs['en']['strings']
    I18N[lc] = {k: s.get(k, en.get(k, k)) for k in en}
    I18N[lc]['_name'] = packs[lc]['_meta']['name']

# ── 指标解读规格：像验血单一样，每项给参考范围 + 含义 + 偏高偏低后果 + 范围出处
# src: apple=Apple 官方规格 | personal=你自己的历史 | lit=锂电通用文献 | none=无权威范围
def spec(key, val, unit, lo, hi, smin, smax, bands, src, refs, fmt="%.1f"):
    return dict(key=key, val=val, unit=unit, lo=lo, hi=hi, smin=smin, smax=smax,
                bands=bands, src=src, refs=refs, fmt=fmt)

cellDelta = max(CELLS)-min(CELLS)
maxRa = max(BD['WeightedRa'])
cycUse = cyc/dcyc*100
peakW = abs(LT['MaximumDischargeCurrent'])*volt/1000

SPECS = [
 spec("stat.temperature", round(temp,1), "°C", 15, 35, -20, 60,
      [(-20,0,"p.tb_freeze","bad"),(0,15,"p.tb_cold","cold"),(15,35,"p.tb_ideal","ok"),
       (35,45,"p.tb_warm","warn"),(45,60,"p.tb_hot","bad")], "lit",
      [("p.t_lifeavg", LT['AverageTemperature']/10, "°C"),
       ("p.t_histband", f"{LT['MinimumTemperature']}–{LT['MaximumTemperature']}", "°C")]),

 spec("insight.factor.balance", cellDelta, "mV", 0, 20, 0, 100,
      [(0,20,"p.cb_ok","ok"),(20,50,"p.cb_mid","warn"),(50,100,"p.cb_bad","bad")], "lit",
      [("p.cb_cells", " / ".join(map(str,CELLS)), "mV")], fmt="%.0f"),

 spec("insight.factor.resistance", maxRa, "mΩ", 0, 130, 0, 400,
      [(0,130,"p.ra_ok","ok"),(130,200,"p.ra_mid","warn"),(200,400,"p.ra_bad","bad")], "none",
      [("p.ra_cells", " / ".join(map(str,BD['WeightedRa'])), "mΩ")], fmt="%.0f"),

 spec("insight.factor.cycles", round(cycUse,1), "%", 0, 50, 0, 100,
      [(0,50,"p.cy_ok","ok"),(50,80,"p.cy_mid","warn"),(80,100,"p.cy_bad","bad")], "apple",
      [("hw.m.cycles", f"{cyc} / {dcyc}", "")]),

 spec("insight.factor.capacity", round(health_sys,1), "%", 80, 100, 50, 100,
      [(50,80,"p.hp_bad","bad"),(80,90,"p.hp_mid","warn"),(90,100,"p.hp_ok","ok")], "apple",
      [("hw.m.raw_max", f"{fcc} / {design}", "mAh")]),

 spec("rt.power", round(watts,1), "W", 0, round(avg_w*1.3,1), 0, 45,
      [(0,round(avg_w*.85,1),"p.pw_low","ok"),(round(avg_w*.85,1),round(avg_w*1.3,1),"p.pw_mid","ok"),
       (round(avg_w*1.3,1),25,"p.pw_high","warn"),(25,45,"p.pw_max","bad")], "personal",
      [("p.p_base", round(avg_w,1), "W"), ("p.p_peak", round(peakW), "W")]),

 spec("hw.m.pack_voltage", round(volt,2), "V", LT['MinimumPackVoltage']/1000, LT['MaximumPackVoltage']/1000,
      LT['MinimumPackVoltage']/1000-0.5, LT['MaximumPackVoltage']/1000+0.5,
      [(LT['MinimumPackVoltage']/1000-0.5, LT['MinimumPackVoltage']/1000,"p.pv_low","bad"),
       (LT['MinimumPackVoltage']/1000, LT['MaximumPackVoltage']/1000,"p.pv_ok","ok"),
       (LT['MaximumPackVoltage']/1000, LT['MaximumPackVoltage']/1000+0.5,"p.pv_high","warn")], "personal",
      [("p.t_histband", f"{LT['MinimumPackVoltage']/1000:.2f}–{LT['MaximumPackVoltage']/1000:.2f}", "V")], fmt="%.2f"),
]

# ── 硬件表：附件中的 63 个逻辑指标全部保留；复合行附带最底层原始字段 ──
def display(value, grouped=False):
    if value is None:
        return "—"
    if isinstance(value, bool):
        return "true" if value else "false"
    if grouped and isinstance(value, int):
        return f"{value:,}"
    return str(value)

def raw_field(name, value, unit=""):
    return {"name": name, "value": display(value), "unit": unit}

def row(k, v, u, mk, rel="verified", nk=None, raw=None, formula=None, substitution=None):
    item = {"k": k, "v": display(v), "u": u, "m": mk, "r": rel, "n": nk}
    if raw:
        item["raw"] = raw
    if formula:
        item["formula"] = formula
        item["substitution"] = substitution or ""
    return item

def compact_json(value):
    if value in (None, [], {}):
        return "—"
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), default=str)

def decode_ascii_integer(value):
    if not isinstance(value, int) or value <= 0:
        return None
    try:
        encoded = f"{value:x}"
        if len(encoded) % 2:
            encoded = "0" + encoded
        decoded = bytes.fromhex(encoded).decode("ascii")
        return decoded if decoded.isprintable() else None
    except (ValueError, UnicodeDecodeError):
        return None

AD = D.get('AdapterDetails') or {}
CD = D.get('ChargerData') or {}
CM = D.get('CarrierMode') or {}
PORTS = D.get('PortControllerInfo') or []

fcc_comp_1, fcc_comp_2 = BD.get('FccComp1'), BD.get('FccComp2')
time_remaining_raw, time_to_empty_raw = D.get('TimeRemaining'), D.get('AvgTimeToEmpty')
time_to_full_raw = D.get('AvgTimeToFull')
system_power_raw = BD.get('SystemPower')
system_inputs = [PT.get('SystemPowerIn'), PT.get('VoltageIn'), PT.get('CurrentIn')]
adapter_contract = [AD.get('AdapterVoltage'), AD.get('Current')]
charge_limits = [CD.get('ChargingVoltage'), CD.get('ChargingCurrent')]
carrier_values = [CM.get('CarrierModeHighVoltage'), CM.get('CarrierModeLowVoltage'), CM.get('CarrierModeStatus')]
chem_values = [BD.get('ChemID'), BD.get('AlgoChemID')]
manufacture_raw = BD.get('ManufactureDate')
manufacture_ascii = decode_ascii_integer(manufacture_raw)
manufacture_value = display(manufacture_raw) + (f" / ASCII {manufacture_ascii}" if manufacture_ascii else "")

port_cycle_value = " · ".join(
    f"C{i + 1} {display(p.get('PortControllerAttachCount'))}/{display(p.get('PortControllerDetachCount'))}"
    for i, p in enumerate(PORTS)
) or "—"
port_cycle_raw = []
port_failure_value = " · ".join(
    f"C{i + 1} {display(p.get('PortControllerCapMismatch'))}/{display(p.get('PortControllerElectionFailReason'))}"
    for i, p in enumerate(PORTS)
) or "—"
port_failure_raw = []
for i, port in enumerate(PORTS):
    port_cycle_raw.extend([
        raw_field(f"PortControllerInfo[{i}].PortControllerAttachCount", port.get('PortControllerAttachCount')),
        raw_field(f"PortControllerInfo[{i}].PortControllerDetachCount", port.get('PortControllerDetachCount')),
    ])
    port_failure_raw.extend([
        raw_field(f"PortControllerInfo[{i}].PortControllerCapMismatch", port.get('PortControllerCapMismatch')),
        raw_field(f"PortControllerInfo[{i}].PortControllerElectionFailReason", port.get('PortControllerElectionFailReason')),
    ])

TABLE = [
 ("hw.group.capacity", [
   row("DesignCapacity", f"{design:,}", "mAh", "hw.m.design_capacity"),
   row("ModelDesignEnergy", f"{design_wh:.1f}" if design_wh else "—", "Wh", "hw.m.model_design_energy", "conditional", "hw.n.model_design_energy",
       [raw_field("hw.model", DATA_MODEL), raw_field("Apple published model specification", design_wh, "Wh")],
       "hw.model → Apple published battery specification", f"{DATA_MODEL} → {design_wh:.1f} Wh" if design_wh else f"{DATA_MODEL} → unavailable"),
   row("AppleRawMaxCapacity", f"{fcc:,}", "mAh", "hw.m.raw_max", "verified", "hw.n.raw_max"),
   row("BatteryData.FccComp1", f"{display(fcc_comp_1)} / {display(fcc_comp_2)}", "mAh", "hw.m.fcc_comp", "verified", "hw.n.fcc_comp",
       [raw_field("BatteryData.FccComp1", fcc_comp_1, "mAh"), raw_field("BatteryData.FccComp2", fcc_comp_2, "mAh")]),
   row("AppleRawCurrentCapacity", f"{cur:,}", "mAh", "hw.m.raw_current", "verified", "hw.n.raw_current"),
   row("CurrentCapacity", D.get('CurrentCapacity'), "%", "hw.m.current_capacity", "verified", "hw.n.current_capacity"),
   row("NominalChargeCapacity", display(D.get('NominalChargeCapacity'), True), "mAh", "hw.m.nominal"),
   row("PackReserve", reserve, "mAh", "hw.m.reserve", "verified", "hw.n.reserve"),
   row("MaxCapacity", D.get('MaxCapacity'), "% / mAh", "hw.m.health_raw", "conditional", "hw.n.health_raw"),
   row("CycleCount", cyc, "", "hw.m.cycles"),
   row("DesignCycleCount9C", f"{dcyc:,}", "", "hw.m.design_cycles", "verified", "hw.n.design_cycles"),
   row("BatteryData.Qmax", " / ".join(map(str, QMAX)), "mAh", "hw.m.qmax", "verified", "hw.n.qmax"),
   row("→ current full energy", f"{current_full_wh:.1f}", "Wh", "hw.m.current_full_energy", "derived", "hw.n.current_full_energy",
       [raw_field("ModelDesignEnergy", design_wh, "Wh"), raw_field("AppleRawMaxCapacity", fcc, "mAh"), raw_field("DesignCapacity", design, "mAh")]),
   row("→ health (system)", f"{health_sys:.1f}", "%", "hw.m.health_system", "derived", "hw.n.health_system",
       [raw_field("AppleRawMaxCapacity", fcc, "mAh"), raw_field("PackReserve", reserve, "mAh"), raw_field("DesignCapacity", design, "mAh")]),
   row("→ health (raw)", f"{health_raw:.1f}", "%", "hw.m.health_raw", "derived", "hw.n.health_raw",
       [raw_field("AppleRawMaxCapacity", fcc, "mAh"), raw_field("DesignCapacity", design, "mAh")]),
   row("→ Qmax − FCC", unusable, "mAh", "hw.m.unusable", "derived", "hw.n.unusable",
       [raw_field("BatteryData.Qmax", " / ".join(map(str, QMAX)), "mAh"), raw_field("AppleRawMaxCapacity", fcc, "mAh")]),
   row("→ deficit total", deficit, "mAh", "hw.m.deficit_total", "derived", "hw.n.deficit_total",
       [raw_field("DesignCapacity", design, "mAh"), raw_field("AppleRawMaxCapacity", fcc, "mAh")]),
   row("→ deficit / cycle", f"{deficit_pc:.1f}", "mAh", "hw.m.deficit_cycle", "derived", "hw.n.deficit_cycle",
       [raw_field("DesignCapacity", design, "mAh"), raw_field("AppleRawMaxCapacity", fcc, "mAh"), raw_field("CycleCount", cyc)])]),

 ("hw.group.runtime", [
   row("TimeRemaining / AvgTimeToEmpty", f"{display(time_remaining_raw)} / {display(time_to_empty_raw)}", "min", "hw.m.time_remaining", "verified", "hw.n.time_remaining",
       [raw_field("TimeRemaining", time_remaining_raw, "min"), raw_field("AvgTimeToEmpty", time_to_empty_raw, "min")]),
   row("AvgTimeToFull", time_to_full_raw, "min", "hw.m.time_to_full", "conditional", "hw.n.time_to_full"),
   row("BatteryInvalidWakeSeconds", D.get('BatteryInvalidWakeSeconds'), "s", "hw.m.invalid_wake", "verified", "hw.n.invalid_wake")]),

 ("hw.group.cells", [
   row("BatteryData.CellVoltage", " / ".join(map(str, CELLS)), "mV", "hw.m.topology", "verified", "hw.n.cell_voltage"),
   row("→ CellVoltage.delta", max(CELLS)-min(CELLS), "mV", "hw.m.cell_delta", "derived", None,
       [raw_field("BatteryData.CellVoltage", " / ".join(map(str, CELLS)), "mV")]),
   row("BatteryData.PresentDOD", " / ".join(map(str, BD.get('PresentDOD', []))), "%", "hw.m.dod"),
   row("BatteryData.CellWom", " / ".join(map(str, BD.get('CellWom', []))) or "—", "—", "hw.m.cell_wom", "questionable", "hw.n.cell_wom"),
   row("BatteryCellDisconnectCount", D.get('BatteryCellDisconnectCount'), "", "hw.m.cell_disconnect"),
   row("PermanentFailureStatus", D.get('PermanentFailureStatus'), "bitmask", "hw.m.pf_status"),
   row("→ pack topology", f"{len(CELLS)}S1P", "—", "hw.m.topology", "derived", "hw.n.topology",
       [raw_field("BatteryData.CellVoltage", " / ".join(map(str, CELLS)), "mV")])]),

 ("hw.group.resistance", [
   row("BatteryData.WeightedRa", " / ".join(map(str, BD['WeightedRa'])), "mΩ", "hw.m.weighted_ra", "verified", "hw.n.weighted_ra"),
   row("BatteryData.Ra00–Ra14", " / ".join(map(str, RA)), "mΩ", "hw.m.weighted_ra", "conditional", "hw.n.weighted_ra",
       [raw_field(f"BatteryData.Ra{i:02d}", value, "mΩ") for i, value in enumerate(RA)]),
   row("BatteryData.ChemicalWeightedRa", BD.get('ChemicalWeightedRa'), "mΩ", "hw.m.chemical_ra", "questionable", "hw.n.chemical_ra")]),

 ("hw.group.electrical", [
   row("Voltage / AppleRawBatteryVoltage", f"{display(D.get('Voltage'))} / {display(D.get('AppleRawBatteryVoltage'))}", "mV", "hw.m.pack_voltage", "verified", None,
       [raw_field("Voltage", D.get('Voltage'), "mV"), raw_field("AppleRawBatteryVoltage", D.get('AppleRawBatteryVoltage'), "mV")]),
   row("Amperage", amp, "mA", "hw.m.smoothed_amperage"),
   row("InstantAmperage", D.get('InstantAmperage'), "mA", "hw.m.instant_amperage"),
   row("Temperature", D.get('Temperature'), "0.01°C", "hw.m.temperature", "conditional", "hw.n.temp_unit"),
   row("VirtualTemperature", D.get('VirtualTemperature'), "0.01°C", "hw.m.virtual_temp", "conditional", "hw.n.temp_unit"),
   row("BatteryData.SystemPower", f"{system_power_raw:.2f}" if isinstance(system_power_raw, (int, float)) else "—", "W", "hw.m.system_power", "verified", "hw.n.system_power")]),

 ("hw.group.telemetry", [
   row("PowerTelemetryData.SystemLoad", display(PT.get('SystemLoad'), True), "mW", "hw.m.system_load"),
   row("PowerTelemetryData.BatteryPower", display(PT.get('BatteryPower'), True), "mW", "hw.m.battery_power"),
   row("PowerTelemetryData.SystemPowerIn/VoltageIn/CurrentIn", " / ".join(display(v) for v in system_inputs), "mW / mV / mA", "hw.m.system_input", "conditional", "hw.n.ac_only",
       [raw_field("PowerTelemetryData.SystemPowerIn", system_inputs[0], "mW"), raw_field("PowerTelemetryData.VoltageIn", system_inputs[1], "mV"), raw_field("PowerTelemetryData.CurrentIn", system_inputs[2], "mA")]),
   row("PowerTelemetryData.AdapterEfficiencyLoss", PT.get('AdapterEfficiencyLoss'), "mW", "hw.m.adapter_efficiency_loss", "questionable", "hw.n.adapter_efficiency_loss"),
   row("PowerTelemetryData.AccumulatedSystemLoad ÷ Count", f"{avg_w:.2f}", "W", "hw.m.accumulated_avg_power", "derived", "hw.n.accumulated_avg_power",
       [raw_field("PowerTelemetryData.AccumulatedSystemLoad", PT.get('AccumulatedSystemLoad')), raw_field("PowerTelemetryData.SystemLoadAccumulatorCount", PT.get('SystemLoadAccumulatorCount'))],
       "averagePower = AccumulatedSystemLoad ÷ SystemLoadAccumulatorCount ÷ 1000",
       f"{PT.get('AccumulatedSystemLoad')} ÷ {PT.get('SystemLoadAccumulatorCount')} ÷ 1000 = {avg_w:.2f} W"),
   row("PowerTelemetryData.AccumulatedWallEnergyEstimate", display(PT.get('AccumulatedWallEnergyEstimate'), True), "raw", "hw.m.wall_energy", "questionable", "hw.n.wall_energy")]),

 ("hw.group.lifetime", [
   row("LifetimeData.MaximumTemperature", LT.get('MaximumTemperature'), "°C", "hw.m.temp_max"),
   row("LifetimeData.MinimumTemperature", LT.get('MinimumTemperature'), "°C", "hw.m.temp_min"),
   row("LifetimeData.AverageTemperature", f"{LT.get('AverageTemperature', 0)/10:.1f}", "°C", "hw.m.temp_avg", "conditional", "hw.n.temp_avg",
       [raw_field("LifetimeData.AverageTemperature", LT.get('AverageTemperature'), "0.1°C")],
       "averageTemperature°C = raw ÷ 10", f"{LT.get('AverageTemperature')} ÷ 10 = {LT.get('AverageTemperature', 0)/10:.1f} °C"),
   row("LifetimeData.TemperatureSamples", display(LT.get('TemperatureSamples'), True), "", "hw.m.temp_samples"),
   row("LifetimeData.MaximumChargeCurrent", display(LT.get('MaximumChargeCurrent'), True), "mA", "hw.m.max_charge_current"),
   row("LifetimeData.MaximumDischargeCurrent", display(LT.get('MaximumDischargeCurrent'), True), "mA", "hw.m.max_discharge_current", "verified", "hw.n.max_discharge"),
   row("LifetimeData.MinimumPackVoltage", display(LT.get('MinimumPackVoltage'), True), "mV", "hw.m.min_pack_voltage", "verified", "hw.n.min_pack_voltage"),
   row("LifetimeData.MaximumPackVoltage", display(LT.get('MaximumPackVoltage'), True), "mV", "hw.m.max_pack_voltage"),
   row("LifetimeData.CycleCountLastQmax", LT.get('CycleCountLastQmax'), "", "hw.m.calib_age"),
   row("→ since last Qmax", calib, "cycles", "hw.m.calib_age", "derived", "hw.n.calib_age",
       [raw_field("CycleCount", cyc), raw_field("LifetimeData.CycleCountLastQmax", LT.get('CycleCountLastQmax'))]),
   row("LifetimeData.TotalOperatingTime", display(LT.get('TotalOperatingTime'), True), "min", "hw.m.total_runtime", "questionable", "hw.n.total_runtime"),
   row("BatteryData.DataFlashWriteCount", display(BD.get('DataFlashWriteCount'), True), "", "hw.m.flash_writes"),
   row("BatteryData.QmaxDisqualificationReason", BD.get('QmaxDisqualificationReason'), "code", "hw.m.qmax_disqualification", "verified", "hw.n.qmax_disqualification"),
   row("BatteryData.DailyMaxSoc / DailyMinSoc", f"{display(BD.get('DailyMaxSoc'))} / {display(BD.get('DailyMinSoc'))}", "%", "hw.m.daily_soc_pair", "conditional", "hw.n.daily_soc",
       [raw_field("BatteryData.DailyMaxSoc", BD.get('DailyMaxSoc'), "%"), raw_field("BatteryData.DailyMinSoc", BD.get('DailyMinSoc'), "%")])]),

 ("hw.group.charger", [
   row("AdapterDetails.Watts", AD.get('Watts'), "W", "hw.m.adapter_watts", "conditional", "hw.n.ac_only"),
   row("AdapterDetails.AdapterVoltage / Current", " / ".join(display(v) for v in adapter_contract), "mV / mA", "hw.m.adapter_contract", "conditional", "hw.n.ac_only",
       [raw_field("AdapterDetails.AdapterVoltage", adapter_contract[0], "mV"), raw_field("AdapterDetails.Current", adapter_contract[1], "mA")]),
   row("AdapterDetails.UsbHvcMenu", compact_json(AD.get('UsbHvcMenu')), "raw", "hw.m.adapter_menu", "conditional", "hw.n.adapter_menu",
       [raw_field("AdapterDetails.UsbHvcMenu", compact_json(AD.get('UsbHvcMenu')))]),
   row("AdapterDetails.Description", AD.get('Description'), "string", "hw.m.adapter_description", "conditional", "hw.n.ac_only"),
   row("ChargerData.ChargingVoltage / ChargingCurrent", " / ".join(display(v) for v in charge_limits), "mV / mA", "hw.m.charge_limits", "conditional", "hw.n.charge_i_limit",
       [raw_field("ChargerData.ChargingVoltage", charge_limits[0], "mV"), raw_field("ChargerData.ChargingCurrent", charge_limits[1], "mA")]),
   row("ChargerData.NotChargingReason", CD.get('NotChargingReason'), "bitmask", "hw.m.not_charging_reason", "questionable", "hw.n.not_charging_reason"),
   row("CarrierMode.CarrierModeHighVoltage/LowVoltage/Status", " / ".join(display(v) for v in carrier_values), "mV / mV / code", "hw.m.carrier_mode", "verified", "hw.n.carrier_mode",
       [raw_field("CarrierMode.CarrierModeHighVoltage", carrier_values[0], "mV"), raw_field("CarrierMode.CarrierModeLowVoltage", carrier_values[1], "mV"), raw_field("CarrierMode.CarrierModeStatus", carrier_values[2])]),
   row("PortControllerInfo[].AttachCount/DetachCount", port_cycle_value, "count", "hw.m.port_cycles", "verified", "hw.n.port_cycles", port_cycle_raw),
   row("PortControllerInfo[].CapMismatch / ElectionFailReason", port_failure_value, "count / code", "hw.m.port_failures", "verified", "hw.n.port_failures", port_failure_raw)]),

 ("hw.group.identity", [
   row("Serial", D.get('Serial'), "string", "hw.m.serial"),
   row("DeviceName", D.get('DeviceName'), "string", "hw.m.gauge_chip"),
   row("BatteryData.ChemID / AlgoChemID", " / ".join(display(v) for v in chem_values), "code", "hw.m.chem_ids", "verified", None,
       [raw_field("BatteryData.ChemID", chem_values[0]), raw_field("BatteryData.AlgoChemID", chem_values[1])]),
   row("BatteryData.ManufactureDate", manufacture_value, "raw / ASCII", "hw.m.manufacture_batch", "questionable", "hw.n.manufacture_batch",
       [raw_field("BatteryData.ManufactureDate", manufacture_raw)],
       "integer → hexadecimal bytes → ASCII", f"{manufacture_raw} → 0x{manufacture_raw:x} → {manufacture_ascii or 'not decodable'}" if isinstance(manufacture_raw, int) else "unavailable"),
   row("BatteryData.DateOfFirstUse", BD.get('DateOfFirstUse'), "raw", "hw.m.first_use", "questionable", "hw.n.first_use"),
   row("GasGaugeFirmwareVersion", D.get('GasGaugeFirmwareVersion'), "", "hw.m.gauge_fw"),
   row("BatteryInstalled / built-in", f"{display(D.get('BatteryInstalled'))} / {display(D.get('built-in'))}", "bool", "hw.m.installed", "verified", None,
       [raw_field("BatteryInstalled", D.get('BatteryInstalled')), raw_field("built-in", D.get('built-in'))]),
   row("hw.model", DATA_MODEL, "identifier", "hw.m.machine_model")]),
]

DATA = dict(ra=RA, cells=CELLS, qmax=QMAX, design=design, fcc=fcc, cur=cur, reserve=reserve,
            cyc=cyc, dcyc=dcyc, healthSys=round(health_sys,1), healthRaw=round(health_raw,1),
            unusable=unusable, aged=aged, deficit=deficit, deficitPC=round(deficit_pc,1), calib=calib,
            ate=ate, onAC=onAC, amp=amp, volt=round(volt,2), watts=round(watts,2),
            designWh=round(design_wh,1) if design_wh else None,
            currentFullWh=round(current_full_wh,2), remainingWh=round(remaining_wh,2),
            energySource=energy_source, modelEnergyName=MODEL_ENERGY_SPEC['name'] if MODEL_ENERGY_SPEC else DATA_MODEL,
            officialWebHours=MODEL_ENERGY_SPEC['webHours'] if MODEL_ENERGY_SPEC else None,
            officialVideoHours=MODEL_ENERGY_SPEC['videoHours'] if MODEL_ENERGY_SPEC else None,
            officialTestCpuCores=MODEL_ENERGY_SPEC['testCpuCores'] if MODEL_ENERGY_SPEC else None,
            officialTestGpuCores=MODEL_ENERGY_SPEC['testGpuCores'] if MODEL_ENERGY_SPEC else None,
            officialTestMemoryGB=MODEL_ENERGY_SPEC['testMemoryGB'] if MODEL_ENERGY_SPEC else None,
            officialTestStorageGB=MODEL_ENERGY_SPEC['testStorageGB'] if MODEL_ENERGY_SPEC else None,
            systemChip=SYSTEM_CHIP, systemCpuCores=SYSTEM_CPU_CORES,
            systemGpuCores=SYSTEM_GPU_CORES, systemMemory=SYSTEM_MEMORY,
            unplugEstimate=unplug_estimate,
            socUI=soc_ui, socRaw=soc_raw, temp=round(temp,1), avgW=round(avg_w,1),
            weightedRa=BD['WeightedRa'], temperatureRaw=D.get('Temperature',0),
            accumulatedSystemLoad=PT['AccumulatedSystemLoad'],
            systemLoadAccumulatorCount=PT['SystemLoadAccumulatorCount'],
            observedDays=1, peakW=round(abs(LT['MaximumDischargeCurrent'])*volt/1000), wh=round(current_full_wh,1), tempAvg=round(LT['AverageTemperature']/10,1),
            tempMax=LT['MaximumTemperature'], tempMin=LT['MinimumTemperature'],
            snapshotAt=snapshot_at, socSource="pmset", model=subprocess.run(['sysctl','-n','hw.model'],capture_output=True,text=True).stdout.strip(),
            remainingHistory=remaining_history, remainingSource="pmset",
            specs=SPECS, table=TABLE, i18n=I18N, langs=LANGS)

tpl = open(f"{ROOT}/Prototype/_template.html", encoding='utf-8').read()
out = tpl.replace("/*__DATA__*/", "const D = " + json.dumps(DATA, ensure_ascii=False) + ";")
open(dst, 'w', encoding='utf-8').write(out)
print(f"已生成 {dst}  ({len(out):,} bytes)")
print(f"  真机数据：设计 {design}mAh / 当前满充 {fcc}mAh / 当前剩余 {min(cur,fcc)}mAh / 本次已用 {max(0,fcc-cur)}mAh / 长期损失 {deficit}mAh")
print(f"  语言：{len(LANGS)} 种，译文取自 app 的语言包")
print(f"  硬件表：{sum(len(r) for _, r in TABLE)} 行 / {len(TABLE)} 组")
