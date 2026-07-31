#!/usr/bin/env python3
"""生成 BatteryMonitor 产品原型定稿 HTML。

两个原则：
  1. 数据取自真机 ioreg，不编数字
  2. 译文直接读 Localization/Languages/*.json —— 与 app 用同一份，不另写一套
"""
import plistlib, subprocess, json, os, glob, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["zh-Hans", "en", "ja", "de", "fr", "ko", "zh-Hant", "es", "it", "pt"]

# ── 真机数据 ────────────────────────────────────────────────
raw = subprocess.run(['ioreg', '-rn', 'AppleSmartBattery', '-a'], capture_output=True).stdout
D = plistlib.loads(raw); D = D[0] if isinstance(D, list) else D
BD, PT = D['BatteryData'], D['PowerTelemetryData']
LT = BD['LifetimeData']
DATA_MODEL = subprocess.run(['sysctl','-n','hw.model'],capture_output=True,text=True).stdout.strip()

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
ate = D.get('AvgTimeToEmpty', 0)
onAC = D.get('ExternalConnected', False)
amp = D.get('Amperage', 0)
volt = D.get('Voltage', 0) / 1000
watts = BD.get('SystemPower', 0) or abs(amp) * volt / 1000
soc_ui = D.get('CurrentCapacity', 0)
soc_raw = BD.get('StateOfCharge', 0)
temp = D.get('Temperature', 0) / 100
avg_w = PT['AccumulatedSystemLoad'] / PT['SystemLoadAccumulatorCount'] / 1000

# ── 译文：从 app 的语言包里取 ────────────────────────────────
packs = {}
for lc in LANGS:
    p = f"{ROOT}/Localization/Languages/{lc}.json"
    packs[lc] = json.load(open(p, encoding='utf-8'))

# 原型里用到的 key（全部来自真实语言包，缺的用 en 兜底）
KEYS = [
 "app.title","insight.section.health","insight.section.power","insight.section.hardware",
 "insight.level.good","insight.level.excellent","insight.factor.capacity","insight.factor.cycles",
 "insight.factor.balance","insight.factor.resistance","insight.factor.temperature","insight.factor.fault",
 "insight.factor.fault_none","insight.life.label","insight.age.label","insight.estimated",
 "insight.power.light","insight.power.idle","insight.expand_factors","hw.field","hw.value","hw.unit",
 "hw.meaning","hw.rel","hw.rel.verified","hw.rel.conditional","hw.rel.questionable","hw.rel.derived",
 "hw.group.cells","hw.group.capacity","hw.group.electrical","hw.group.charger","hw.group.telemetry",
 "hw.group.identity","hw.group.lifetime","hw.group.derived","hw.m.cell_delta","hw.m.weighted_ra",
 "hw.m.qmax","hw.m.design_capacity","hw.m.raw_max","hw.m.raw_current","hw.m.reserve","hw.m.cycles",
 "hw.m.design_cycles","hw.m.pack_voltage","hw.m.system_power","hw.m.temp_max","hw.m.temp_avg",
 "hw.m.min_pack_voltage","hw.m.calib_age","hw.m.unusable","hw.m.deficit_cycle","hw.m.deficit_total",
 "hw.m.health_system","hw.m.health_raw","hw.m.topology","hw.m.serial","hw.m.gauge_chip",
 "hw.n.qmax","hw.n.cell_voltage","hw.n.reserve","hw.n.raw_max","hw.n.raw_current","hw.n.unusable",
 "hw.n.deficit_cycle","hw.n.deficit_total","hw.n.calib_age","hw.n.topology","hw.n.health_system",
 "hw.n.health_raw","hw.n.design_cycles","hw.n.weighted_ra","hw.n.min_pack_voltage",
 "hw.m.dod","hw.m.nominal","hw.m.smoothed_amperage","hw.m.instant_amperage","hw.m.virtual_temp","hw.m.adapter_watts","hw.m.charge_v_limit","hw.m.charge_i_limit","hw.m.not_charging_reason","hw.m.system_load","hw.m.battery_power","hw.m.power_in","hw.m.gauge_fw","hw.m.chem_id","hw.m.flash_writes","hw.m.pf_status","hw.m.cell_disconnect","hw.m.machine_model","hw.m.temp_min","hw.m.max_charge_current","hw.m.max_discharge_current","hw.m.max_pack_voltage","hw.m.temp_samples","hw.m.daily_max_soc","hw.m.daily_min_soc","hw.n.ac_only","hw.n.charge_i_limit","hw.n.not_charging_reason","hw.n.temp_unit","hw.n.temp_avg","hw.n.max_discharge","hw.n.total_runtime","hw.n.daily_soc","hw.n.system_power",
 "stat.temperature","stat.cycles","stat.health","stat.adapter","gauge.ac","gauge.battery",
 "rt.voltage","rt.amperage","rt.power","rt.temperature","rt.percent","rt.title",
]
I18N = {}
for lc in LANGS:
    s = packs[lc]['strings']; en = packs['en']['strings']
    I18N[lc] = {k: s.get(k, en.get(k, k)) for k in KEYS}
    I18N[lc]['_name'] = packs[lc]['_meta']['name']

# 原型专属文案（app 里没有的叙事性内容）—— 只做 4 种主要语言，其余回落英文
EXTRA = {
"p.seg_now":      {"zh-Hans":"现在还有","en":"In there now","ja":"現在の残量","de":"Aktuell drin"},
"p.seg_used":     {"zh-Hans":"已用掉","en":"Used","ja":"使用済み","de":"Verbraucht"},
"p.seg_now_d":    {"zh-Hans":"此刻电池里真实剩下的电荷。充电会把它填回「能用的」上限，这部分是可逆的。",
                   "en":"What is actually in the cells right now. Charging refills it up to the usable ceiling — this part is reversible.",
                   "ja":"今この瞬間セルに残っている電荷。充電すれば使用可能上限まで戻る、可逆的な部分です。",
                   "de":"Was gerade tatsächlich in den Zellen steckt. Laden füllt es bis zur nutzbaren Grenze wieder auf — dieser Teil ist reversibel."},
"p.derive":       {"zh-Hans":"推导链：出厂 {d} → 电芯化学总容量 Qmax {q}（差额 = 已老化）→ 可用满充 FCC {f}（差额 = 取不出来）→ 当前剩余 {c}",
                   "en":"Chain: design {d} → chemical total Qmax {q} (gap = ageing) → usable full charge FCC {f} (gap = unreachable) → currently {c}",
                   "ja":"導出：設計 {d} → 化学総容量 Qmax {q}（差 = 劣化）→ 使用可能満充電 FCC {f}（差 = 取り出せない分）→ 現在 {c}",
                   "de":"Kette: Design {d} → chemische Gesamtkapazität Qmax {q} (Differenz = Alterung) → nutzbare Ladung FCC {f} (Differenz = unerreichbar) → aktuell {c}"},
"p.where_title":  {"zh-Hans":"你买的容量去哪了","en":"Where your capacity went","ja":"買った容量はどこへ","de":"Wo Ihre Kapazität blieb"},
"p.where_head":   {"zh-Hans":"你买的 {a} mAh，实际能用 {b}","en":"You paid for {a} mAh — you can actually use {b}",
                   "ja":"購入時 {a} mAh のうち、実際に使えるのは {b}","de":"Bezahlt: {a} mAh — nutzbar: {b}"},
"p.seg_use":      {"zh-Hans":"你能用的","en":"Actually usable","ja":"実際に使える分","de":"Tatsächlich nutzbar"},
"p.seg_un":       {"zh-Hans":"取不出来","en":"Unreachable","ja":"取り出せない分","de":"Nicht erreichbar"},
"p.seg_age":      {"zh-Hans":"已老化损失","en":"Lost to ageing","ja":"劣化で失われた分","de":"Durch Alterung verloren"},
"p.seg_use_d":    {"zh-Hans":"这就是系统显示的 0–100%。你的 0% 就是关机点，不会真的耗到电芯空。",
                   "en":"This is what the 0–100% you see maps to. Your 0% is the shutdown point, not an empty cell.",
                   "ja":"画面の 0〜100% はこの範囲です。0% は停止点であり、セルが空になるわけではありません。",
                   "de":"Darauf bilden die angezeigten 0–100 % ab. Ihre 0 % sind der Abschaltpunkt, keine leere Zelle."},
"p.seg_un_d":     {"zh-Hans":"化学上还在电池里，但放到这里电压已经太低，任何软件都取不出来。电量计自己算出的（Qmax − FCC）。",
                   "en":"Chemically still in the cells, but the voltage there is too low for anything to draw it. Computed by the gauge itself (Qmax − FCC).",
                   "ja":"化学的にはセル内に残っていますが、その領域では電圧が低すぎて取り出せません。電量計自身の計算値（Qmax − FCC）。",
                   "de":"Chemisch noch in den Zellen, aber die Spannung ist dort zu niedrig, um sie zu nutzen. Vom Gauge berechnet (Qmax − FCC)."},
"p.seg_age_d":    {"zh-Hans":"{n} 次循环里被副反应永久扣押的锂。这部分只会增加，不会回来。",
                   "en":"Lithium permanently locked away by side reactions over {n} cycles. This only grows.",
                   "ja":"{n} サイクルの副反応で恒久的に失われたリチウム。増える一方で戻りません。",
                   "de":"Über {n} Zyklen durch Nebenreaktionen dauerhaft gebundenes Lithium. Wird nur mehr."},
"p.why_deeper":   {"zh-Hans":"为什么会有「取不出来」的部分？（技术细节）","en":"Why is part of it unreachable? (technical)",
                   "ja":"なぜ取り出せない分があるのか（技術詳細）","de":"Warum ist ein Teil unerreichbar? (technisch)"},
"p.ra_legend":    {"zh-Hans":"电池内阻随电量变化","en":"Internal resistance vs charge level",
                   "ja":"残量に対する内部抵抗","de":"Innenwiderstand über Ladezustand"},
"p.ra_outlier":   {"zh-Hans":"端点数据不足，不参与结论","en":"Endpoint under-sampled — excluded",
                   "ja":"端点はデータ不足のため除外","de":"Randpunkt zu wenig erfasst – ausgeschlossen"},
"p.ra_take":      {"zh-Hans":"电量越低内阻越高，接近放空时达到中段的 {x}。电压 = 开路电压 − 电流×内阻，内阻一高电压就撑不住，于是最后那段电荷还没放出来电压就已经跌破截止线。电量计据此把那部分从可用容量里扣掉。",
                   "en":"Resistance climbs as charge falls, reaching {x} the mid-range level near empty. Since voltage = open-circuit − current×resistance, high resistance collapses the terminal voltage before that last charge can be drawn — so the gauge excludes it from usable capacity.",
                   "ja":"残量が減るほど内部抵抗は上がり、空に近づくと中間域の {x} に達します。端子電圧 = 開放電圧 − 電流×抵抗 なので、抵抗が高いと最後の電荷を取り出す前に電圧が遮断値を割ります。電量計はその分を使用可能容量から除外します。",
                   "de":"Der Widerstand steigt mit sinkender Ladung und erreicht nahe leer das {x} des mittleren Bereichs. Da Klemmenspannung = Leerlauf − Strom×Widerstand gilt, bricht sie ein, bevor die letzte Ladung entnommen werden kann — das Gauge zieht sie daher von der nutzbaren Kapazität ab."},
"p.tagline":      {"zh-Hans":"电池监控中心","en":"Battery Monitor","ja":"バッテリーモニター","de":"Batterie-Monitor"},
"p.remaining":    {"zh-Hans":"还能用多久","en":"Time remaining","ja":"あと何時間使えるか","de":"Verbleibende Zeit"},
"p.src_note":     {"zh-Hans":"直接来自电量计芯片，不是我们估的","en":"Straight from the gauge chip — not our estimate",
                   "ja":"電量計チップの値そのもの（当アプリの推定ではありません）","de":"Direkt vom Gauge-Chip – keine eigene Schätzung"},
"p.why_title":    {"zh-Hans":"为什么最后 20% 掉得特别快","en":"Why the last 20% drains so fast",
                   "ja":"なぜ残り20%から急に減るのか","de":"Warum die letzten 20 % so schnell weg sind"},
"p.why_sub":      {"zh-Hans":"你的电池不是被「用完」的 —— 是电压塌了先关机","en":"Your battery is never “used up” — the voltage collapses first",
                   "ja":"バッテリーは「使い切る」のではなく、電圧が落ちて先に停止します","de":"Der Akku wird nie „leer“ – die Spannung bricht vorher ein"},
"p.decay_title":  {"zh-Hans":"电池是怎么变弱的","en":"How the battery gets weaker",
                   "ja":"バッテリーはどう弱るのか","de":"Wie der Akku schwächer wird"},
"p.decay_lead":   {"zh-Hans":"不是「变弱」，是每次充放电都有一小撮锂离子被永久扣押",
                   "en":"Not “weakening” — each cycle permanently sequesters a pinch of lithium",
                   "ja":"「弱る」のではなく、充放電のたびにリチウムが少しずつ恒久的に失われます",
                   "de":"Kein „Schwächerwerden“ – jeder Zyklus bindet dauerhaft etwas Lithium"},
"p.per_cycle":    {"zh-Hans":"每循环扣押","en":"Per cycle","ja":"1サイクルあたり","de":"Pro Zyklus"},
"p.cycles_done":  {"zh-Hans":"已完成循环","en":"Cycles done","ja":"完了サイクル","de":"Zyklen"},
"p.total_locked": {"zh-Hans":"累计扣押","en":"Total locked away","ja":"累計損失","de":"Insgesamt gebunden"},
"p.trend_title":  {"zh-Hans":"变化趋势","en":"Trends","ja":"推移","de":"Verlauf"},
"p.trend_sub":    {"zh-Hans":"系统只告诉你容量还剩百分之几，但你在意的单位是小时",
                   "en":"The system tells you a percentage. What you care about is hours.",
                   "ja":"システムは％しか示しません。知りたいのは「何時間」です。",
                   "de":"Das System nennt Prozent. Interessant sind aber Stunden."},
"p.geek":         {"zh-Hans":"全部指标（极客向）","en":"All metrics (for the curious)","ja":"全指標（マニア向け）","de":"Alle Messwerte"},
"p.hover_hint":   {"zh-Hans":"悬停任意行查看可靠性说明与注意事项","en":"Hover any row for reliability notes and caveats",
                   "ja":"行にカーソルを合わせると信頼性の注記が出ます","de":"Zeile überfahren für Hinweise zur Verlässlichkeit"},
"p.unusable_ex":  {"zh-Hans":"化学上还在电池里，但电压塌陷前取不出来。这个数是电量计自己算的。",
                   "en":"Chemically present but unreachable before voltage collapse. Computed by the gauge itself.",
                   "ja":"化学的には残っていますが、電圧低下により取り出せません。電量計自身の計算値です。",
                   "de":"Chemisch vorhanden, aber vor dem Spannungseinbruch nicht nutzbar. Vom Gauge selbst berechnet."},
"p.nonlinear":    {"zh-Hans":"不要拿它外推寿命：锂电衰减前期快、之后趋平",
                   "en":"Do not extrapolate: lithium fade is fast early, then flattens",
                   "ja":"外挿は禁物：リチウムの劣化は初期が速く、その後緩やかになります",
                   "de":"Nicht extrapolieren: Li-Alterung ist früh schnell, dann flach"},
}
for lc in LANGS:
    for k, v in EXTRA.items():
        I18N[lc][k] = v.get(lc, v["en"])

# ── 硬件表（结构与 app 的 HardwareDetailView.build 对齐）────────
def row(k, v, u, mk, rel="verified", nk=None):
    return {"k": k, "v": v, "u": u, "m": mk, "r": rel, "n": nk}
TABLE = [
 ("hw.group.cells", [
   row("BatteryData.CellVoltage", " / ".join(map(str, CELLS)), "mV", "hw.m.topology", "verified", "hw.n.cell_voltage"),
   row("→ CellVoltage.delta", str(max(CELLS)-min(CELLS)), "mV", "hw.m.cell_delta", "derived"),
   row("BatteryData.WeightedRa", " / ".join(map(str, BD['WeightedRa'])), "mΩ", "hw.m.weighted_ra", "verified", "hw.n.weighted_ra"),
   row("BatteryData.Qmax", " / ".join(map(str, QMAX)), "mAh", "hw.m.qmax", "verified", "hw.n.qmax"),
   row("BatteryData.PresentDOD", " / ".join(map(str, BD.get('PresentDOD', []))), "%", "hw.m.dod"),
   row("BatteryData.Ra00–Ra14", " ".join(map(str, RA)), "mΩ", "hw.m.weighted_ra", "conditional", "hw.n.weighted_ra")]),
 ("hw.group.capacity", [
   row("DesignCapacity", f"{design:,}", "mAh", "hw.m.design_capacity"),
   row("AppleRawMaxCapacity", f"{fcc:,}", "mAh", "hw.m.raw_max", "verified", "hw.n.raw_max"),
   row("AppleRawCurrentCapacity", f"{cur:,}", "mAh", "hw.m.raw_current", "verified", "hw.n.raw_current"),
   row("NominalChargeCapacity", f"{D.get('NominalChargeCapacity',0):,}", "mAh", "hw.m.nominal"),
   row("PackReserve", str(reserve), "mAh", "hw.m.reserve", "verified", "hw.n.reserve"),
   row("CycleCount", str(cyc), "", "hw.m.cycles"),
   row("DesignCycleCount9C", f"{dcyc:,}", "", "hw.m.design_cycles", "verified", "hw.n.design_cycles"),
   row("MaxCapacity", str(D.get('MaxCapacity',0)), "%", "hw.m.health_raw", "conditional", "hw.n.health_raw")]),
 ("hw.group.electrical", [
   row("AppleRawBatteryVoltage", f"{D.get('AppleRawBatteryVoltage',0):,}", "mV", "hw.m.pack_voltage"),
   row("Amperage", str(amp), "mA", "hw.m.smoothed_amperage"),
   row("InstantAmperage", str(D.get('InstantAmperage',0)), "mA", "hw.m.instant_amperage"),
   row("Temperature", f"{D.get('Temperature',0)}", "0.01°C", "hw.m.virtual_temp", "conditional", "hw.n.temp_unit"),
   row("VirtualTemperature", f"{D.get('VirtualTemperature',0)}", "0.01°C", "hw.m.virtual_temp", "conditional", "hw.n.temp_unit"),
   row("BatteryData.SystemPower", f"{watts:.2f}", "W", "hw.m.system_power", "verified", "hw.n.system_power")]),
 ("hw.group.charger", [
   row("AdapterDetails.Watts", str(D.get('AdapterDetails',{}).get('Watts','—')), "W", "hw.m.adapter_watts", "conditional", "hw.n.ac_only"),
   row("ChargerData.ChargingVoltage", str(D.get('ChargerData',{}).get('ChargingVoltage',0)), "mV", "hw.m.charge_v_limit"),
   row("ChargerData.ChargingCurrent", str(D.get('ChargerData',{}).get('ChargingCurrent',0)), "mA", "hw.m.charge_i_limit", "conditional", "hw.n.charge_i_limit"),
   row("ChargerData.NotChargingReason", str(D.get('ChargerData',{}).get('NotChargingReason',0)), "", "hw.m.not_charging_reason", "questionable", "hw.n.not_charging_reason")]),
 ("hw.group.telemetry", [
   row("PowerTelemetryData.SystemLoad", f"{PT.get('SystemLoad',0):,}", "mW", "hw.m.system_load"),
   row("PowerTelemetryData.BatteryPower", f"{PT.get('BatteryPower',0):,}", "mW", "hw.m.battery_power"),
   row("PowerTelemetryData.SystemPowerIn", f"{PT.get('SystemPowerIn',0):,}", "mW", "hw.m.power_in", "conditional", "hw.n.ac_only"),
   row("→ AccumulatedSystemLoad ÷ n", f"{avg_w:.1f}", "W", "hw.m.system_power", "derived", "hw.n.system_power")]),
 ("hw.group.identity", [
   row("Serial", D.get('Serial','—'), "—", "hw.m.serial"),
   row("DeviceName", D.get('DeviceName','—'), "—", "hw.m.gauge_chip"),
   row("GasGaugeFirmwareVersion", str(D.get('GasGaugeFirmwareVersion',0)), "", "hw.m.gauge_fw"),
   row("BatteryData.ChemID", str(BD.get('ChemID',0)), "", "hw.m.chem_id"),
   row("BatteryData.DataFlashWriteCount", f"{BD.get('DataFlashWriteCount',0):,}", "", "hw.m.flash_writes"),
   row("PermanentFailureStatus", str(D.get('PermanentFailureStatus',0)), "", "hw.m.pf_status"),
   row("BatteryCellDisconnectCount", str(D.get('BatteryCellDisconnectCount',0)), "", "hw.m.cell_disconnect"),
   row("hw.model", DATA_MODEL, "—", "hw.m.machine_model")]),
 ("hw.group.lifetime", [
   row("LifetimeData.TotalOperatingTime", f"{LT['TotalOperatingTime']:,}", "min", "hw.m.total_runtime", "questionable", "hw.n.total_runtime"),
   row("LifetimeData.MaximumTemperature", str(LT['MaximumTemperature']), "°C", "hw.m.temp_max"),
   row("LifetimeData.MinimumTemperature", str(LT['MinimumTemperature']), "°C", "hw.m.temp_min"),
   row("LifetimeData.AverageTemperature", f"{LT['AverageTemperature']/10:.1f}", "°C", "hw.m.temp_avg", "conditional", "hw.n.temp_avg"),
   row("LifetimeData.MaximumChargeCurrent", f"{LT['MaximumChargeCurrent']:,}", "mA", "hw.m.max_charge_current"),
   row("LifetimeData.MaximumDischargeCurrent", f"{LT['MaximumDischargeCurrent']:,}", "mA", "hw.m.max_discharge_current", "verified", "hw.n.max_discharge"),
   row("LifetimeData.MinimumPackVoltage", f"{LT['MinimumPackVoltage']:,}", "mV", "hw.m.min_pack_voltage", "verified", "hw.n.min_pack_voltage"),
   row("LifetimeData.MaximumPackVoltage", f"{LT['MaximumPackVoltage']:,}", "mV", "hw.m.max_pack_voltage"),
   row("LifetimeData.TemperatureSamples", f"{LT['TemperatureSamples']:,}", "", "hw.m.temp_samples"),
   row("LifetimeData.CycleCountLastQmax", str(LT['CycleCountLastQmax']), "", "hw.m.calib_age"),
   row("BatteryData.DailyMaxSoc", str(BD.get('DailyMaxSoc',0)), "%", "hw.m.daily_max_soc", "conditional", "hw.n.daily_soc"),
   row("BatteryData.DailyMinSoc", str(BD.get('DailyMinSoc',0)), "%", "hw.m.daily_min_soc", "conditional", "hw.n.daily_soc")]),
 ("hw.group.derived", [
   row("→ health (system)", f"{health_sys:.1f}", "%", "hw.m.health_system", "derived", "hw.n.health_system"),
   row("→ health (raw)", f"{health_raw:.1f}", "%", "hw.m.health_raw", "derived", "hw.n.health_raw"),
   row("→ Qmax − FCC", str(unusable), "mAh", "hw.m.unusable", "derived", "hw.n.unusable"),
   row("→ deficit / cycle", f"{deficit_pc:.1f}", "mAh", "hw.m.deficit_cycle", "derived", "hw.n.deficit_cycle"),
   row("→ deficit total", str(deficit), "mAh", "hw.m.deficit_total", "derived", "hw.n.deficit_total"),
   row("→ since last Qmax", str(calib), "", "hw.m.calib_age", "derived", "hw.n.calib_age"),
   row("→ pack topology", f"{len(CELLS)}S1P", "—", "hw.m.topology", "derived", "hw.n.topology")]),
]

DATA = dict(ra=RA, cells=CELLS, qmax=QMAX, design=design, fcc=fcc, cur=cur, reserve=reserve,
            cyc=cyc, dcyc=dcyc, healthSys=round(health_sys,1), healthRaw=round(health_raw,1),
            unusable=unusable, aged=aged, deficit=deficit, deficitPC=round(deficit_pc,1), calib=calib,
            ate=ate, onAC=onAC, amp=amp, volt=round(volt,2), watts=round(watts,2),
            socUI=soc_ui, socRaw=soc_raw, temp=round(temp,1), avgW=round(avg_w,1),
            model=subprocess.run(['sysctl','-n','hw.model'],capture_output=True,text=True).stdout.strip(),
            table=TABLE, i18n=I18N, langs=LANGS)

tpl = open(f"{ROOT}/Prototype/_template.html", encoding='utf-8').read()
out = tpl.replace("/*__DATA__*/", "const D = " + json.dumps(DATA, ensure_ascii=False) + ";")
dst = f"{ROOT}/Prototype/battery-final.html"
open(dst, 'w', encoding='utf-8').write(out)
print(f"已生成 {dst}  ({len(out):,} bytes)")
print(f"  真机数据：健康 {health_sys:.1f}% / 循环 {cyc} / 取不出来 {unusable}mAh / 每循环扣押 {deficit_pc:.1f}mAh")
print(f"  语言：{len(LANGS)} 种，译文取自 app 的语言包")
print(f"  硬件表：{sum(len(r) for _, r in TABLE)} 行 / {len(TABLE)} 组")
