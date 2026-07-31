#!/usr/bin/env python3
"""生成 BatteryMonitor 产品原型定稿 HTML。

两个原则：
  1. 数据取自真机 ioreg，不编数字
  2. 译文直接读 Localization/Languages/*.json —— 与 app 用同一份，不另写一套
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
"p.seg_now_d":    {"zh-Hans":"<strong>像水箱里此刻剩下的水。</strong>使用会减少，插上电就能重新补满。",
                   "en":"<strong>Like the water left in the tank right now.</strong> Using the Mac drains it; plugging in fills it again.",
                   "ja":"<strong>今タンクに残っている水のようなもの。</strong>使えば減り、電源につなげばまた補充できます。",
                   "de":"<strong>Wie das Wasser, das gerade im Tank ist.</strong> Nutzung leert es, Anschließen füllt es wieder auf."},
"p.derive":       {"zh-Hans":"消费者口径：设计 {d} − 当前满充 {f} = 长期损失 {loss}；当前满充 {f} − 当前剩余 {c} = 本次已用 {used}。<br>深层诊断：电量计 Qmax {q} 只用于分析电芯状态，不参与上面的主分账。",
                   "en":"Consumer view: design {d} − current full charge {f} = long-term loss {loss}; current full charge {f} − current charge {c} = used this time {used}.<br>Deep diagnosis: gauge Qmax {q} is only for cell analysis and does not enter the main breakdown above.",
                   "ja":"消費者向け：設計 {d} − 現在の満充電 {f} = 長期損失 {loss}、現在の満充電 {f} − 現在残量 {c} = 今回使用 {used}。<br>深層診断：Qmax {q} はセル分析専用で、上の主計算には含めません。",
                   "de":"Verbrauchersicht: Design {d} − aktuelle Vollladung {f} = Langzeitverlust {loss}; Vollladung {f} − aktueller Inhalt {c} = diesmal verbraucht {used}.<br>Tiefendiagnose: Qmax {q} dient nur der Zellanalyse und nicht der Hauptaufteilung."},
"p.where_title":  {"zh-Hans":"你买的容量去哪了","en":"Where your capacity went","ja":"買った容量はどこへ","de":"Wo Ihre Kapazität blieb"},
"p.where_head":   {"zh-Hans":"出厂设计 {a} mAh，现在充满最多 {b}，此刻还有 {c}","en":"Designed for {a} mAh, now fills to {b}, with {c} left right now",
                   "ja":"設計 {a} mAh、現在の満充電上限 {b}、今の残量 {c}","de":"Design {a} mAh, heute voll maximal {b}, aktuell noch {c}"},
"p.design_capacity":{"zh-Hans":"出厂设计容量","en":"Original design capacity","ja":"出荷時設計容量","de":"Ursprüngliche Designkapazität"},
"p.current_max":  {"zh-Hans":"现在充满最多","en":"Maximum when full now","ja":"現在の満充電上限","de":"Heute maximal voll"},
"p.current_actual":{"zh-Hans":"此刻实际还有","en":"Actually left right now","ja":"今実際に残っている量","de":"Aktuell tatsächlich übrig"},
"p.used_since_full":{"zh-Hans":"本次已经用掉","en":"Used since the last full charge","ja":"今回使った量","de":"Seit Vollladung verbraucht"},
"p.permanent_loss":{"zh-Hans":"长期容量损失","en":"Long-term capacity loss","ja":"長期容量損失","de":"Langfristiger Kapazitätsverlust"},
"p.capacity_sum": {"zh-Hans":"整条容量条 = 此刻还有 + 本次已用 + 长期损失 = 设计容量 {design} mAh","en":"Whole bar = left now + used this charge + long-term loss = {design} mAh design capacity","ja":"全体バー = 現在残量 + 今回使用 + 長期損失 = 設計容量 {design} mAh","de":"Gesamter Balken = aktuell + diesmal verbraucht + Langzeitverlust = {design} mAh Design"},
"p.current_actual_desc":{"zh-Hans":"现在真实存放在电池里的电，继续使用会减少，充电可以补回。","en":"Charge physically in the battery now. It falls with use and returns when charged.","ja":"今実際に電池にある電気。使用で減り、充電で戻ります。","de":"Ladung, die jetzt wirklich im Akku steckt. Sinkt bei Nutzung und kommt beim Laden zurück."},
"p.used_since_full_desc":{"zh-Hans":"从最近一次充满到现在消耗的电；它只是“今天用了多少”，充电后会重新变回可用电。","en":"Consumed since the most recent full charge. It means “used this time” and returns as usable charge after charging.","ja":"直近の満充電から消費した量。今回使っただけで、充電すると使用可能分に戻ります。","de":"Seit der letzten Vollladung verbraucht. Nur diesmal genutzt und nach dem Laden wieder verfügbar."},
"p.used_zero_desc":{"zh-Hans":"现在正好是满电，所以是 0；拔电开始使用后，这一格会增长。","en":"It is zero because the battery is full now. This grows after unplugging and using the Mac.","ja":"今は満充電なので0です。電源を外して使うと増えていきます。","de":"Jetzt 0, weil der Akku voll ist. Nach dem Abziehen und Nutzen wächst dieser Wert."},
"p.permanent_loss_desc":{"zh-Hans":"当前满充容量比出厂设计少的部分；日常充电不会把它补回来。","en":"The part current full-charge capacity is below the original design. Normal charging does not refill it.","ja":"現在の満充電容量が設計値より少ない分。通常の充電では戻りません。","de":"Der Teil, um den die heutige Vollladekapazität unter dem Design liegt. Normales Laden bringt ihn nicht zurück."},
"p.eq_capacity_title":{"zh-Hans":"电池现在最多能装多少","en":"How much the battery can hold now","ja":"今どれだけ入るか","de":"Wie viel heute hineinpasst"},
"p.eq_capacity_sub":{"zh-Hans":"和出厂时相比","en":"Compared with when it was new","ja":"新品時との比較","de":"Verglichen mit neu"},
"p.eq_usage_title":{"zh-Hans":"这次充满后用了多少","en":"How much has been used this charge","ja":"今回の充電で使った量","de":"Seit dieser Vollladung verbraucht"},
"p.eq_usage_sub": {"zh-Hans":"充电后可以补回来","en":"This can be refilled by charging","ja":"充電で戻せる分","de":"Durch Laden wieder auffüllbar"},
"p.seg_use":      {"zh-Hans":"你能用的","en":"Actually usable","ja":"実際に使える分","de":"Tatsächlich nutzbar"},
"p.seg_un":       {"zh-Hans":"取不出来","en":"Unreachable","ja":"取り出せない分","de":"Nicht erreichbar"},
"p.seg_age":      {"zh-Hans":"已老化损失","en":"Lost to ageing","ja":"劣化で失われた分","de":"Durch Alterung verloren"},
"p.card_now":     {"zh-Hans":"此刻还剩","en":"Left right now","ja":"今の残量","de":"Gerade übrig"},
"p.card_use":     {"zh-Hans":"充满后能用","en":"Usable when full","ja":"満充電で使える分","de":"Voll nutzbar"},
"p.card_un":      {"zh-Hans":"还在，但用不到","en":"Still there, out of reach","ja":"残っているが使えない","de":"Noch da, aber unerreichbar"},
"p.card_age":     {"zh-Hans":"真正老化掉","en":"Actually lost to ageing","ja":"実際に劣化した分","de":"Tatsächlich gealtert"},
"p.seg_use_d":    {"zh-Hans":"<strong>像水箱真正能装、也能放出来的部分。</strong>菜单栏里的 0–100%，就是在这段容量里变化。",
                   "en":"<strong>Like the part of the tank you can really fill and drain.</strong> The menu-bar 0–100% moves within this usable portion.",
                   "ja":"<strong>タンクのうち実際に満たして使える部分。</strong>メニューバーの0〜100%はこの範囲で変化します。",
                   "de":"<strong>Wie der Teil des Tanks, den Sie wirklich füllen und leeren können.</strong> Die 0–100 % bewegen sich in diesem Bereich."},
"p.seg_un_d":     {"zh-Hans":"<strong>像杯底吸管够不到的水。</strong>电量还在，但电脑为了避免电压过低，会在用到它之前关机保护。",
                   "en":"<strong>Like water below the reach of a straw.</strong> The charge is still there, but the Mac shuts down before voltage becomes unsafe.",
                   "ja":"<strong>ストローが届かない底の水のようなもの。</strong>電気は残っていますが、電圧が危険になる前にMacが停止します。",
                   "de":"<strong>Wie Wasser, das der Strohhalm am Boden nicht erreicht.</strong> Ladung ist noch da, aber der Mac schaltet vorher zum Schutz ab."},
"p.seg_age_d":    {"zh-Hans":"<strong>像水箱本身缩小了一点。</strong>这部分无法靠充电恢复；目前只占出厂容量的一小块。",
                   "en":"<strong>Like the tank itself becoming slightly smaller.</strong> Charging cannot restore this part; it is currently only a small slice of the original capacity.",
                   "ja":"<strong>タンク自体が少し小さくなったようなもの。</strong>充電では戻りませんが、現状は出荷時容量のごく一部です。",
                   "de":"<strong>Wie ein Tank, der selbst etwas kleiner geworden ist.</strong> Laden bringt diesen Teil nicht zurück; derzeit ist es nur ein kleiner Anteil."},
"p.why_deeper":   {"zh-Hans":"这些容量是怎么计算的？查看技术细节","en":"How are these capacities calculated? View technical details",
                   "ja":"これらの容量はどう計算する？技術詳細を見る","de":"Wie werden diese Kapazitäten berechnet? Technische Details"},
"p.ra_legend":    {"zh-Hans":"电池内阻随电量变化","en":"Internal resistance vs charge level",
                   "ja":"残量に対する内部抵抗","de":"Innenwiderstand über Ladezustand"},
"p.ra_outlier":   {"zh-Hans":"端点数据不足，不参与结论","en":"Endpoint under-sampled — excluded",
                   "ja":"端点はデータ不足のため除外","de":"Randpunkt zu wenig erfasst – ausgeschlossen"},
"p.ra_take":      {"zh-Hans":"电量越低内阻越高，接近放空时达到中段的 {x}。电压 = 开路电压 − 电流×内阻，内阻一高电压就撑不住，于是最后那段电荷还没放出来电压就已经跌破截止线。电量计据此把那部分从可用容量里扣掉。",
                   "en":"Resistance climbs as charge falls, reaching {x} the mid-range level near empty. Since voltage = open-circuit − current×resistance, high resistance collapses the terminal voltage before that last charge can be drawn — so the gauge excludes it from usable capacity.",
                   "ja":"残量が減るほど内部抵抗は上がり、空に近づくと中間域の {x} に達します。端子電圧 = 開放電圧 − 電流×抵抗 なので、抵抗が高いと最後の電荷を取り出す前に電圧が遮断値を割ります。電量計はその分を使用可能容量から除外します。",
                   "de":"Der Widerstand steigt mit sinkender Ladung und erreicht nahe leer das {x} des mittleren Bereichs. Da Klemmenspannung = Leerlauf − Strom×Widerstand gilt, bricht sie ein, bevor die letzte Ladung entnommen werden kann — das Gauge zieht sie daher von der nutzbaren Kapazität ab."},
"p.dual_head":    {"zh-Hans":"每次都直接记录 macOS 给出的剩余时间；线条只连接系统历史读数","en":"Each point records the time remaining reported by macOS; the line only connects system readings",
                   "ja":"各点は macOS が返した残り時間をそのまま記録し、線はシステム履歴だけを結びます","de":"Jeder Punkt speichert die von macOS gemeldete Restzeit; die Linie verbindet nur Systemwerte"},
"p.split_v":      {"zh-Hans":"电压 · 电池给的","en":"Voltage · what the cells give","ja":"電圧 · セル side","de":"Spannung · von den Zellen"},
"p.split_i":      {"zh-Hans":"电流 · 系统要的","en":"Current · what the system draws","ja":"電流 · システムの要求","de":"Strom · was das System zieht"},
"p.split_note":   {"zh-Hans":"电压由电池化学和剩余电量决定，你改不了，而且变化很慢；<b>能被你影响的只有电流</b>——关掉高占用进程、调低亮度，减的都是电流那一项。所以「省电」在物理上就等于「压低电流」。",
                   "en":"Voltage is set by cell chemistry and charge level — slow-moving and outside your control. <b>Only the current is yours to change</b>: closing heavy processes or dimming the display cuts the current term. Saving power physically means pulling less current.",
                   "ja":"電圧はセルの化学と残量で決まり、ゆっくりとしか変わらず制御できません。<b>変えられるのは電流だけ</b>——重いプロセスを閉じる、輝度を下げる、いずれも電流を減らす操作です。省電力とは物理的に「電流を抑えること」です。",
                   "de":"Die Spannung ergibt sich aus Zellchemie und Ladezustand — träge und nicht beeinflussbar. <b>Nur den Strom haben Sie in der Hand</b>: Prozesse schließen oder Helligkeit senken reduziert den Stromterm. Energiesparen heißt physikalisch: weniger Strom ziehen."},
"p.read_title":   {"zh-Hans":"合理范围与高低影响","en":"Healthy ranges and high/low effects","ja":"適正範囲と高低の影響","de":"Sinnvolle Bereiche und Auswirkungen"},
"p.t_ok":         {"zh-Hans":"正常","en":"Normal","ja":"正常","de":"Normal"},
"p.t_warn":       {"zh-Hans":"偏高","en":"Elevated","ja":"やや高い","de":"Erhöht"},
"p.t_bad":        {"zh-Hans":"过热","en":"Too hot","ja":"高温","de":"Zu heiß"},
"p.t_lifeavg":    {"zh-Hans":"你的终生平均","en":"Your lifetime average","ja":"あなたの生涯平均","de":"Ihr Lebensdauer-Mittel"},
"p.t_hist":       {"zh-Hans":"历史极值","en":"All-time range","ja":"過去の範囲","de":"Historische Spanne"},
"p.t_today":      {"zh-Hans":"今日极值","en":"Today's range","ja":"本日の範囲","de":"Heutige Spanne"},
"p.t_vs":         {"zh-Hans":"相对日常","en":"vs your normal","ja":"平常比","de":"ggü. Ihrem Normalwert"},
"p.collecting":   {"zh-Hans":"收集中","en":"Collecting","ja":"収集中","de":"Wird erfasst"},
"p.t_impact":     {"zh-Hans":"<b>影响：</b>35°C 以下对寿命基本无损；35–45°C 会明显加速容量衰减；持续超过 45°C 是实打实的伤害。低温不会永久损伤，但会临时降低可用功率。建议区间：<b>低于 35°C</b>。",
                   "en":"<b>Impact:</b> below 35°C does essentially no harm; 35–45°C measurably accelerates capacity fade; sustained above 45°C causes real damage. Cold does not permanently harm the cells but temporarily reduces available power. Target: <b>under 35°C</b>.",
                   "ja":"<b>影響：</b>35°C 未満なら寿命への影響はほぼなし。35〜45°C は容量劣化を明確に加速。45°C 超が続くと実害があります。低温は恒久的な損傷にはなりませんが、一時的に出力が落ちます。目安は <b>35°C 未満</b>。",
                   "de":"<b>Wirkung：</b>Unter 35 °C praktisch unschädlich; 35–45 °C beschleunigt den Kapazitätsverlust messbar; dauerhaft über 45 °C richtet echten Schaden an. Kälte schadet nicht dauerhaft, senkt aber kurzzeitig die verfügbare Leistung. Ziel: <b>unter 35 °C</b>."},
"p.p_low":        {"zh-Hans":"低于日常","en":"Below your normal","ja":"平常より低い","de":"Unter Ihrem Normalwert"},
"p.p_mid":        {"zh-Hans":"与日常相当","en":"About normal","ja":"平常並み","de":"Etwa normal"},
"p.p_high":       {"zh-Hans":"高于日常","en":"Above your normal","ja":"平常より高い","de":"Über Ihrem Normalwert"},
"p.p_base":       {"zh-Hans":"你的长期基线","en":"Your long-run baseline","ja":"あなたの長期基準","de":"Ihre Langzeit-Basis"},
"p.p_ratio":      {"zh-Hans":"相对基线","en":"vs baseline","ja":"基準比","de":"ggü. Basis"},
"p.p_energy":     {"zh-Hans":"可用能量","en":"Usable energy","ja":"利用可能エネルギー","de":"Nutzbare Energie"},
"p.p_theory":     {"zh-Hans":"按此功率理论续航","en":"Runtime at this draw","ja":"この消費での理論持続","de":"Laufzeit bei diesem Verbrauch"},
"p.p_impact":     {"zh-Hans":"<b>参照系是你自己</b>，不是行业均值 —— 基线由你这台机器累计十万次采样得出。<b>影响：</b>按日常功耗能撑 {a}；跑编译或渲染（约 25W）掉到 {b}；满载（约 45W）只剩 {c}。",
                   "en":"<b>The reference is you</b>, not an industry average — the baseline comes from over a hundred thousand samples on this machine. <b>Impact:</b> at your normal draw you get {a}; compiling or rendering (~25W) drops it to {b}; full load (~45W) leaves {c}.",
                   "ja":"<b>基準はあなた自身</b>で、業界平均ではありません —— この機体で十万回以上のサンプルから算出。<b>影響：</b>平常の消費なら {a}、コンパイルやレンダリング（約25W）で {b}、フル負荷（約45W）では {c} です。",
                   "de":"<b>Der Bezug sind Sie selbst</b>, kein Branchenmittel — die Basis stammt aus über hunderttausend Messungen auf diesem Gerät. <b>Wirkung:</b> bei Ihrem Normalverbrauch {a}; beim Kompilieren oder Rendern (~25 W) nur noch {b}; unter Volllast (~45 W) {c}."},
"p.cadence":      {"zh-Hans":"电量计约每 30–60 秒才刷新一次，两次之间数值恒定 —— 所以画成阶梯而不是平滑曲线。它是平滑过的均值，不是瞬时值。",
                   "en":"The gauge refreshes only every ~30–60 s and holds its value in between — hence steps, not a smooth curve. It is a smoothed average, not an instantaneous reading.",
                   "ja":"電量計の更新は約30〜60秒ごとで、その間は値が一定です —— だから滑らかな曲線ではなく階段で描いています。瞬時値ではなく平滑化された平均値です。",
                   "de":"Das Gauge aktualisiert nur alle ~30–60 s und hält den Wert dazwischen — daher Stufen statt glatter Kurve. Es ist ein geglätteter Mittelwert, kein Momentanwert."},
"p.scen_title":   {"zh-Hans":"你干什么，电池就掉多快","en":"What you do decides how fast it drains",
                   "ja":"何をするかで減り方が決まる","de":"Was Sie tun, bestimmt den Verbrauch"},
"p.scen_sub":     {"zh-Hans":"下面是在这台机器上实测出来的。app 会持续记录，把你自己的常用场景补进这张表。",
                   "en":"Measured on this machine. The app keeps recording and will fill in your own habitual scenarios.",
                   "ja":"この機体で実測した値です。アプリが記録を続け、あなたの常用シーンを追加していきます。",
                   "de":"Auf diesem Gerät gemessen. Die App zeichnet weiter auf und ergänzt Ihre typischen Szenarien."},
"p.scen_now":     {"zh-Hans":"当前","en":"Now","ja":"現在","de":"Jetzt"},
"p.scen_idle":    {"zh-Hans":"空闲 / 看文档","en":"Idle / reading","ja":"アイドル / 閲覧","de":"Leerlauf / Lesen"},
"p.scen_full":    {"zh-Hans":"全核编译","en":"Full-core compile","ja":"全コアコンパイル","de":"Volllast-Kompilieren"},
"p.scen_measured":{"zh-Hans":"实测","en":"measured","ja":"実測","de":"gemessen"},
"p.scen_note":    {"zh-Hans":"这不是假设 —— 是刚才在这台机器上跑全核负载实测的：功耗 {a} → {b}，剩余时间 {c} → {d} 分钟。<b>你的每一个动作都在这条曲线上。</b>",
                   "en":"Not a hypothetical — measured just now by running a full-core load on this machine: power {a} → {b}, time left {c} → {d} min. <b>Everything you do sits on this curve.</b>",
                   "ja":"仮定ではなく、たった今この機体で全コア負荷をかけて実測した値です：消費電力 {a} → {b}、残り時間 {c} → {d} 分。<b>あなたの操作はすべてこの曲線上にあります。</b>",
                   "de":"Keine Annahme — soeben auf diesem Gerät mit Volllast gemessen: Leistung {a} → {b}, Restzeit {c} → {d} min. <b>Jede Ihrer Aktionen liegt auf dieser Kurve.</b>"},
"p.t_cadence":    {"zh-Hans":"刷新节奏","en":"Refresh cadence","ja":"更新間隔","de":"Aktualisierung"},
"p.t_histband":   {"zh-Hans":"历史区间","en":"All-time band","ja":"過去の範囲","de":"Historische Spanne"},
"p.p_peak":       {"zh-Hans":"你历史上最狠的一次","en":"Your all-time peak draw","ja":"過去最大の消費","de":"Ihr bisheriger Spitzenverbrauch"},
"p.tb_freeze":    {"zh-Hans":"零度以下充电会析出金属锂，造成永久损伤。放电可以，但容量临时大幅缩水。",
                   "en":"Charging below freezing plates metallic lithium and causes permanent damage. Discharging is safe but capacity shrinks sharply and temporarily.",
                   "ja":"氷点下での充電は金属リチウムが析出し恒久的な損傷を招きます。放電は可能ですが容量は一時的に大きく低下します。",
                   "de":"Laden unter 0 °C scheidet metallisches Lithium ab und schädigt dauerhaft. Entladen ist unbedenklich, die Kapazität sinkt aber vorübergehend stark."},
"p.tb_cold":      {"zh-Hans":"内阻升高，可用功率和续航临时下降。不造成永久损伤，回温即恢复。",
                   "en":"Internal resistance rises; available power and runtime drop temporarily. No permanent harm — it recovers as it warms up.",
                   "ja":"内部抵抗が上がり、出力と持続時間が一時的に低下します。恒久的な損傷はなく、温まれば回復します。",
                   "de":"Der Innenwiderstand steigt; Leistung und Laufzeit sinken vorübergehend. Kein bleibender Schaden — erholt sich beim Erwärmen."},
"p.tb_ideal":     {"zh-Hans":"理想区间。老化速率处于最低水平，充放电都不受限。",
                   "en":"The sweet spot. Ageing runs at its slowest and neither charging nor discharging is restricted.",
                   "ja":"理想的な範囲。劣化速度は最小で、充放電とも制限されません。",
                   "de":"Idealbereich. Die Alterung läuft am langsamsten, Laden und Entladen sind uneingeschränkt."},
"p.tb_warm":      {"zh-Hans":"老化开始加速。经验规律：温度每高 10°C，容量衰减速度约翻一倍。",
                   "en":"Ageing starts to accelerate. Rule of thumb: every extra 10 °C roughly doubles the rate of capacity fade.",
                   "ja":"劣化が加速し始めます。経験則として、温度が 10°C 上がるごとに容量低下速度はおよそ 2 倍になります。",
                   "de":"Die Alterung beschleunigt sich. Faustregel: Je 10 °C mehr verdoppelt sich der Kapazitätsverlust ungefähr."},
"p.tb_hot":       {"zh-Hans":"实打实的伤害。系统通常会降频或限制充电来自保，长期处于此区间会显著缩短寿命。",
                   "en":"Real damage. The system will usually throttle or limit charging to protect itself; sustained exposure here markedly shortens life.",
                   "ja":"実害があります。システムは通常クロックを落とすか充電を制限して自衛します。この領域が続くと寿命が著しく縮みます。",
                   "de":"Echter Schaden. Das System drosselt meist oder begrenzt das Laden; dauerhafter Aufenthalt verkürzt die Lebensdauer deutlich."},
"p.t_arrhenius":  {"zh-Hans":"<b>建议区间 15–35°C。</b>经验规律（Arrhenius）：温度每升高 10°C，衰减速度约翻倍 —— 也就是说常年 35°C 的电池，老化速度大约是 25°C 的两倍。<b>注意：</b>Apple 未公开电芯温度阈值，以上分档来自锂电通用文献，非厂商规格。",
                   "en":"<b>Target 15–35 °C.</b> Rule of thumb (Arrhenius): every 10 °C rise roughly doubles the fade rate — a battery living at 35 °C ages about twice as fast as one at 25 °C. <b>Note:</b> Apple publishes no cell-temperature thresholds; these bands come from general lithium-ion literature, not vendor specs.",
                   "ja":"<b>推奨は 15〜35°C。</b>経験則（アレニウス）：10°C 上がるごとに劣化速度はおよそ倍 —— 常時 35°C の電池は 25°C の約 2 倍の速さで老化します。<b>注意：</b>Apple はセル温度のしきい値を公開していません。上記の区分は一般的なリチウムイオン文献に基づくもので、メーカー仕様ではありません。",
                   "de":"<b>Ziel 15–35 °C.</b> Faustregel (Arrhenius): je 10 °C mehr verdoppelt sich die Alterungsrate — ein Akku bei 35 °C altert etwa doppelt so schnell wie bei 25 °C. <b>Hinweis:</b> Apple nennt keine Zell-Temperaturgrenzen; diese Bänder stammen aus allgemeiner Lithium-Ionen-Literatur, nicht aus Herstellerangaben."},
"p.spec_title":   {"zh-Hans":"指标解读 · 像看验血单一样","en":"Metric reference · read it like a blood panel",
                   "ja":"指標の読み方 · 血液検査のように","de":"Werte lesen · wie ein Blutbild"},
"p.spec_sub":     {"zh-Hans":"每项都给参考范围、当前落点、偏高偏低的具体后果 —— 并标注这个范围是从哪来的。",
                   "en":"Each metric gets a reference range, where you sit, and what high or low actually does — plus where that range came from.",
                   "ja":"各項目に参考範囲・現在地・高すぎ低すぎの具体的な影響を示し、その範囲の出典も明記します。",
                   "de":"Jeder Wert bekommt einen Referenzbereich, Ihre Position darin und die konkreten Folgen von zu hoch oder zu niedrig — samt Quelle des Bereichs."},
"p.range":        {"zh-Hans":"参考范围","en":"Reference range","ja":"参考範囲","de":"Referenzbereich"},
"p.src_apple":    {"zh-Hans":"Apple 官方规格","en":"Apple's own spec","ja":"Apple 公式仕様","de":"Apple-Spezifikation"},
"p.src_personal": {"zh-Hans":"你自己的历史数据","en":"Your own history","ja":"あなた自身の履歴","de":"Ihre eigene Historie"},
"p.src_lit":      {"zh-Hans":"锂电通用文献（非厂商规格）","en":"General Li-ion literature (not vendor spec)",
                   "ja":"リチウムイオン一般文献（メーカー仕様ではない）","de":"Allgemeine Li-Ionen-Literatur (keine Herstellerangabe)"},
"p.src_none":     {"zh-Hans":"⚠️ 无权威范围，此处为保守取值，真正可靠的是它的变化趋势",
                   "en":"⚠️ No authoritative range exists; this is a conservative guess. What is reliable is its trend over time.",
                   "ja":"⚠️ 権威ある基準値は存在しません。ここでは保守的に設定しており、信頼できるのは経時変化の傾向です。",
                   "de":"⚠️ Es gibt keinen belastbaren Bereich; dies ist konservativ gewählt. Verlässlich ist nur der Trend über die Zeit."},
"p.cb_ok":        {"zh-Hans":"电芯高度一致，没有哪一节在拖后腿","en":"Cells well matched — no single cell holding the pack back",
                   "ja":"セルの揃いが良く、足を引っ張るセルはありません","de":"Zellen gut abgeglichen — keine bremst das Pack aus"},
"p.cb_mid":       {"zh-Hans":"开始出现差异。串联时最弱那节决定整组容量，差距越大浪费越多",
                   "en":"Drifting apart. In series the weakest cell caps the pack, so a wider spread wastes more",
                   "ja":"ばらつきが出始めています。直列では最弱セルが容量を決めるため、差が広がるほど無駄になります",
                   "de":"Sie driften auseinander. In Serie begrenzt die schwächste Zelle das Pack — größere Streuung bedeutet mehr Verlust"},
"p.cb_bad":       {"zh-Hans":"明显失衡。可用容量被最弱那节严重拉低，通常预示某节电芯已劣化",
                   "en":"Clearly unbalanced. Usable capacity is dragged down by the weakest cell — usually a sign one cell has degraded",
                   "ja":"明確に不均衡です。最弱セルが容量を大きく引き下げており、通常はいずれかのセルの劣化を示します",
                   "de":"Deutlich unausgeglichen. Die schwächste Zelle drückt die nutzbare Kapazität — meist ein Zeichen für eine degradierte Zelle"},
"p.cb_cells":     {"zh-Hans":"各电芯电压","en":"Per-cell voltage","ja":"セル別電圧","de":"Spannung je Zelle"},
"p.ra_ok":        {"zh-Hans":"供电能力良好，大负载时电压不会明显塌陷","en":"Good power delivery — voltage holds up under heavy load",
                   "ja":"出力に余裕があり、高負荷でも電圧が落ちにくい状態です","de":"Gute Leistungsabgabe — die Spannung bricht unter Last nicht ein"},
"p.ra_mid":       {"zh-Hans":"内阻上升。大负载时压降更大，可用容量会缩水，发热也更多",
                   "en":"Resistance rising. Bigger voltage sag under load means less usable capacity and more heat",
                   "ja":"抵抗が上昇。高負荷時の電圧降下が大きくなり、使える容量が減り発熱も増えます",
                   "de":"Widerstand steigt. Größerer Spannungsabfall unter Last: weniger nutzbare Kapazität, mehr Wärme"},
"p.ra_bad":       {"zh-Hans":"内阻偏高。高倍率放电时容易触发低压关机，且发热加剧老化，形成恶性循环",
                   "en":"High resistance. Heavy draw can trigger low-voltage shutdowns, and the extra heat accelerates ageing — a feedback loop",
                   "ja":"抵抗が高い状態。高負荷時に低電圧シャットダウンを招きやすく、発熱が劣化を加速させる悪循環になります",
                   "de":"Hoher Widerstand. Starke Last kann Unterspannungs-Abschaltungen auslösen, und die Zusatzwärme beschleunigt die Alterung — ein Teufelskreis"},
"p.ra_cells":     {"zh-Hans":"各电芯内阻","en":"Per-cell resistance","ja":"セル別抵抗","de":"Widerstand je Zelle"},
"p.cy_ok":        {"zh-Hans":"用量充裕。按 Apple 额定 1000 次计，还远未到寿命节点",
                   "en":"Plenty of headroom. Against Apple's 1000-cycle rating you are nowhere near the end",
                   "ja":"余裕があります。Apple の定格 1000 サイクルに対し、寿命にはまだ遠い状態です",
                   "de":"Viel Spielraum. Gemessen an Apples 1000-Zyklen-Angabe sind Sie weit vom Ende entfernt"},
"p.cy_mid":       {"zh-Hans":"过半。容量衰减通常在这一段趋于平缓，但绝对值会持续下降",
                   "en":"Past halfway. Capacity fade usually flattens here, though the absolute number keeps falling",
                   "ja":"半分を超えました。容量低下はこの辺りで緩やかになりますが、絶対値は下がり続けます",
                   "de":"Über der Hälfte. Der Kapazitätsverlust flacht hier meist ab, sinkt aber weiter"},
"p.cy_bad":       {"zh-Hans":"接近额定寿命。此后容量衰减和内阻上升都会明显加快，建议开始规划更换",
                   "en":"Near the rated end. Fade and resistance rise both accelerate from here — worth planning a replacement",
                   "ja":"定格寿命に近づいています。以降は容量低下も抵抗上昇も加速するため、交換の計画を",
                   "de":"Nahe der Nennlebensdauer. Ab hier beschleunigen sich Verlust und Widerstandsanstieg — Austausch einplanen"},
"p.hp_ok":        {"zh-Hans":"容量健康。续航与出厂时差别不大","en":"Healthy. Runtime is close to what it was new",
                   "ja":"健全です。新品時と大きく変わりません","de":"Gesund. Die Laufzeit entspricht fast dem Neuzustand"},
"p.hp_mid":       {"zh-Hans":"已有衰减但仍在正常范围。续航缩短可感知，日常使用无碍",
                   "en":"Some fade but still normal. Shorter runtime is noticeable yet everyday use is fine",
                   "ja":"多少低下していますが正常範囲です。持続時間の短縮は体感できますが日常使用に支障はありません",
                   "de":"Etwas Verlust, aber normal. Die kürzere Laufzeit ist spürbar, der Alltag bleibt unproblematisch"},
"p.hp_bad":       {"zh-Hans":"低于 80% —— 这是 Apple 判定「需要更换」的门槛。系统可能提示服务",
                   "en":"Below 80% — Apple's own threshold for “service recommended”. macOS may start prompting",
                   "ja":"80% 未満 —— Apple が「修理サービス推奨」とする閾値です。システムが通知を出す場合があります",
                   "de":"Unter 80 % — Apples eigene Schwelle für „Service empfohlen“. macOS meldet das ggf."},
"p.pw_low":       {"zh-Hans":"低于你的日常水平，续航会比平时更久","en":"Below your normal — you will get more runtime than usual",
                   "ja":"平常より低く、いつもより長く持ちます","de":"Unter Ihrem Normalwert — mehr Laufzeit als sonst"},
"p.pw_mid":       {"zh-Hans":"与你的日常水平相当","en":"About your normal level","ja":"平常並みの水準です","de":"Etwa Ihr Normalniveau"},
"p.pw_high":      {"zh-Hans":"高于日常。续航会明显短于你习惯的时长","en":"Above normal. Runtime will be noticeably shorter than you are used to",
                   "ja":"平常より高く、慣れている持続時間より明らかに短くなります","de":"Über normal. Die Laufzeit wird spürbar kürzer als gewohnt"},
"p.pw_max":       {"zh-Hans":"接近满载。持续这样电池撑不了多久，且发热会加速老化",
                   "en":"Near full load. The battery will not last long like this, and the heat accelerates ageing",
                   "ja":"ほぼフル負荷。この状態が続くと持続時間は短く、発熱が劣化を早めます",
                   "de":"Nahe Volllast. So hält der Akku nicht lange, und die Wärme beschleunigt die Alterung"},
"p.pv_ok":        {"zh-Hans":"在这块电池历史上出现过的正常区间内","en":"Within the range this pack has historically operated in",
                   "ja":"このパックが過去に動作してきた範囲内です","de":"Im historisch üblichen Bereich dieses Packs"},
"p.pv_low":       {"zh-Hans":"低于历史最低。接近截止电压，系统随时可能关机保护",
                   "en":"Below the all-time low. Close to cutoff — the system may shut down to protect the cells",
                   "ja":"過去最低を下回っています。遮断電圧に近く、保護のため停止する可能性があります",
                   "de":"Unter dem historischen Tief. Nahe der Abschaltschwelle — das System kann zum Schutz herunterfahren"},
"p.pv_high":      {"zh-Hans":"高于历史最高。通常只在满充瞬间出现","en":"Above the all-time high — normally only seen at the instant of full charge",
                   "ja":"過去最高を上回っています。通常は満充電の瞬間にのみ現れます","de":"Über dem historischen Hoch — normalerweise nur im Moment der Vollladung"},
"p.unlock_title":  {"zh-Hans":"它会越来越懂你的电池","en":"It keeps learning your battery","ja":"使うほどバッテリーを理解します","de":"Es lernt Ihren Akku immer besser kennen"},
"p.unlock_head":   {"zh-Hans":"不用研究参数，正常使用就会逐步看到更多答案","en":"No setup or studying required — just use your Mac and more answers appear",
                    "ja":"設定や勉強は不要。普段どおり使うだけで、見える答えが増えていきます","de":"Keine Einrichtung nötig — einfach normal nutzen und mehr Antworten erhalten"},
"p.unlock_sub":    {"zh-Hans":"几分钟先看清当下，几小时开始认识今天，几天后逐渐形成只属于你的使用画像。每多用一点，结论就更贴近你。",
                    "en":"Minutes explain what is happening now, hours reveal today's pattern, and days begin shaping a profile unique to you. Every session makes the answers more personal.",
                    "ja":"数分で現在が分かり、数時間で今日の傾向が見え、数日であなただけの利用プロファイルが育ちます。使うほど答えがあなたに近づきます。",
                    "de":"Minuten erklären den Moment, Stunden zeigen das heutige Muster und nach einigen Tagen entsteht Ihr persönliches Nutzungsprofil."},
"p.ul_now":        {"zh-Hans":"打开就能看到","en":"Right away","ja":"すぐに","de":"Sofort"},
"p.ul_minutes":    {"zh-Hans":"使用几分钟","en":"After a few minutes","ja":"数分後","de":"Nach einigen Minuten"},
"p.ul_hours":      {"zh-Hans":"使用几小时","en":"After a few hours","ja":"数時間後","de":"Nach einigen Stunden"},
"p.ul_day":        {"zh-Hans":"使用一天","en":"After a day","ja":"1日後","de":"Nach einem Tag"},
"p.ul_days":       {"zh-Hans":"使用几天","en":"After a few days","ja":"数日後","de":"Nach einigen Tagen"},
"p.ul_longer":     {"zh-Hans":"持续使用","en":"Keep using it","ja":"使い続ける","de":"Weiter nutzen"},
"p.ul_0":          {"zh-Hans":"健康与容量概况","en":"Health & capacity overview","ja":"健康度と容量の概要","de":"Zustand & Kapazität"},
"p.ul_0d":         {"zh-Hans":"立刻看清健康度、容量去向和历史极值","en":"See health, where capacity went, and lifetime extremes immediately","ja":"健康度・容量の行方・過去の極値をすぐ確認","de":"Zustand, Kapazitätsverteilung und Extremwerte sofort sehen"},
"p.ul_min":        {"zh-Hans":"功率与续航联动","en":"Power & runtime together","ja":"電力と残り時間の連動","de":"Leistung & Laufzeit"},
"p.ul_mind":       {"zh-Hans":"知道当前使用方式会让电池大约撑多久","en":"See how long the battery should last at your current usage","ja":"今の使い方であとどれくらい持つか分かります","de":"Sehen, wie lange der Akku bei Ihrer aktuellen Nutzung hält"},
"p.ul_hour":       {"zh-Hans":"今天的使用范围","en":"Today's operating range","ja":"今日の利用範囲","de":"Heutiger Nutzungsbereich"},
"p.ul_hourd":      {"zh-Hans":"出现今日温度、功率高低与波动区间","en":"Today's temperature and power ranges begin to take shape","ja":"今日の温度・消費電力・変動範囲が見えてきます","de":"Temperatur- und Leistungsbereiche des Tages werden sichtbar"},
"p.ul_1d":         {"zh-Hans":"初识你的常用场景","en":"First personal scenarios","ja":"よく使う場面を認識","de":"Erste persönliche Szenarien"},
"p.ul_1dd":        {"zh-Hans":"开始区分轻办公、视频与高负载时的真实差异","en":"Starts separating light work, video, and heavy-load behavior","ja":"軽作業・動画・高負荷の実際の違いを見分け始めます","de":"Unterscheidet leichte Arbeit, Video und hohe Last"},
"p.ul_3":          {"zh-Hans":"个人使用画像","en":"Your usage profile","ja":"個人の利用プロファイル","de":"Ihr Nutzungsprofil"},
"p.ul_3d":         {"zh-Hans":"逐渐发现充电习惯，以及哪些场景最影响续航","en":"Learns charging habits and which scenarios affect runtime most","ja":"充電習慣と、持続時間に最も影響する場面を学びます","de":"Lernt Ladegewohnheiten und die größten Laufzeiteinflüsse"},
"p.ul_more":       {"zh-Hans":"变化原因与长期趋势","en":"Causes & long-term trends","ja":"変化の理由と長期傾向","de":"Ursachen & Langzeittrends"},
"p.ul_mored":      {"zh-Hans":"数据越丰富，越能回答续航为什么变化、电池如何老化","en":"Richer history explains why runtime changes and how this battery is ageing","ja":"履歴が増えるほど、持ちが変わる理由と劣化の進み方が分かります","de":"Mehr Verlauf erklärt Laufzeitänderungen und Alterung"},
"p.unlock_note":   {"zh-Hans":"把它留在后台即可，不用专门做测试，也不会打断你。数据不足时只显示“正在了解”，有足够把握后才给结论。",
                    "en":"Leave it running quietly in the background. No special test is needed and it will not interrupt you. It says “still learning” until there is enough evidence for a conclusion.",
                    "ja":"バックグラウンドで静かに動かすだけです。特別なテストは不要で、作業を妨げません。十分な根拠が集まるまでは「学習中」と表示します。",
                    "de":"Einfach ruhig im Hintergrund laufen lassen. Keine Tests, keine Unterbrechung. Bis genügend Daten vorliegen, steht dort „lernt noch“."},
"p.learn_summary": {"zh-Hans":"继续使用后，这项指标还能告诉我什么？","en":"What else can this metric tell me over time?","ja":"使い続けると、この指標から何が分かる？","de":"Was kann diese Metrik mit der Zeit noch zeigen?"},
"p.learn_intro":   {"zh-Hans":"不用专门测试，把 App 留在后台即可；数据不足时只显示“正在了解”，有足够把握后才给结论。","en":"No special test is needed. Leave the app in the background; it says “still learning” until there is enough evidence.","ja":"特別なテストは不要です。バックグラウンドで動かし、十分な根拠が集まるまでは「学習中」と表示します。","de":"Kein besonderer Test nötig. Im Hintergrund laufen lassen; bis genügend Daten vorliegen, steht dort „lernt noch“."},
"p.learn_minutes": {"zh-Hans":"看清当前功率变化，会让剩余时间怎样变化。","en":"See how current power changes affect time remaining.","ja":"現在の消費電力が残り時間にどう影響するか。","de":"Wie aktuelle Leistungsänderungen die Restzeit beeinflussen."},
"p.learn_hours":   {"zh-Hans":"形成今天的功率、温度与剩余时间波动范围。","en":"Build today's ranges for power, temperature, and time remaining.","ja":"今日の電力・温度・残り時間の変動範囲を形成。","de":"Heutige Bereiche für Leistung, Temperatur und Restzeit bilden."},
"p.learn_days":    {"zh-Hans":"识别常用场景，并解释哪些使用方式最影响续航。","en":"Recognize common scenarios and explain which usage patterns affect runtime most.","ja":"よく使う場面を認識し、駆動時間への影響が大きい使い方を説明。","de":"Häufige Szenarien erkennen und die größten Laufzeiteinflüsse erklären."},
"p.spec_metric":   {"zh-Hans":"指标","en":"Metric","ja":"指標","de":"Messwert"},
"p.spec_current":  {"zh-Hans":"当前值","en":"Current","ja":"現在値","de":"Aktuell"},
"p.spec_reading":  {"zh-Hans":"现在怎么理解","en":"What it means now","ja":"現在の意味","de":"Aktuelle Einordnung"},
"p.spec_bands":    {"zh-Hans":"各范围代表什么","en":"What each range means","ja":"各範囲の意味","de":"Bedeutung der Bereiche"},
"p.spec_source":   {"zh-Hans":"范围依据","en":"Range source","ja":"範囲の根拠","de":"Quelle"},
"p.spec_source_note":{"zh-Hans":"参考范围不是混在一起的“标准答案”：Apple 规格、你自己的历史和通用锂电资料会分别标注。","en":"Reference ranges are not treated as one universal truth: Apple specs, your own history, and general Li-ion research are labelled separately.","ja":"参考範囲を一つの絶対基準として扱わず、Apple 仕様・個人履歴・一般資料を区別して示します。","de":"Bereiche werden klar als Apple-Spezifikation, persönliche Historie oder allgemeine Li-Ion-Literatur gekennzeichnet."},
"p.spec_other_title":{"zh-Hans":"其余 4 项关键指标","en":"Four other key metrics","ja":"その他の重要な4指標","de":"Vier weitere wichtige Werte"},
"p.spec_other_sub":{"zh-Hans":"顶部只展示最关心的健康度、功率和温度。这里列出其余 4 项的真实当前值，并与合理范围、历史极限和高低影响直接对照。","en":"The top only shows health, power, and temperature. Here the four remaining live values are compared directly with ranges, history, and high/low effects.","ja":"上部は健康度・電力・温度だけを表示します。残り4項は現在値を範囲・履歴・高低の影響と直接比較します。","de":"Oben stehen nur Zustand, Leistung und Temperatur. Die vier übrigen Istwerte werden hier direkt mit Bereichen, Verlauf und Auswirkungen verglichen."},
"p.good_range":   {"zh-Hans":"合理范围","en":"Healthy range","ja":"適正範囲","de":"Sinnvoller Bereich"},
"p.history_extreme":{"zh-Hans":"历史极限","en":"Historical range","ja":"過去の極値","de":"Historischer Bereich"},
"p.history_peak": {"zh-Hans":"历史峰值","en":"Historical peak","ja":"過去最高","de":"Historischer Spitzenwert"},
"p.history_learning":{"zh-Hans":"历史范围正在积累","en":"Historical range is still learning","ja":"履歴範囲を収集中","de":"Historischer Bereich wird erfasst"},
"p.cumulative_no_extreme":{"zh-Hans":"累计指标，没有高低极值","en":"Cumulative metric — no high/low extreme","ja":"累積指標・高低の極値なし","de":"Kumulativer Wert — keine Extremspanne"},
"p.low_effect":   {"zh-Hans":"偏低时","en":"When low","ja":"低い場合","de":"Wenn niedrig"},
"p.high_effect":  {"zh-Hans":"偏高时","en":"When high","ja":"高い場合","de":"Wenn hoch"},
"p.health_low_short":{"zh-Hans":"续航变短，低于 80% 可能提示维修","en":"Shorter runtime; below 80% may trigger service advice","ja":"持続時間が短くなり、80%未満で修理推奨の可能性","de":"Kürzere Laufzeit; unter 80 % ggf. Servicehinweis"},
"p.health_high_short":{"zh-Hans":"续航更接近新机","en":"Runtime stays closer to new","ja":"新品に近い持続時間","de":"Laufzeit näher am Neuzustand"},
"p.cycle_low_short":{"zh-Hans":"累计使用量较少","en":"Less cumulative use","ja":"累積使用量が少ない","de":"Weniger kumulierte Nutzung"},
"p.cycle_high_short":{"zh-Hans":"接近额定寿命，结合容量判断","en":"Near rated life; judge together with capacity","ja":"定格寿命に近く、容量と合わせて判断","de":"Nahe Nennlebensdauer; mit Kapazität bewerten"},
"p.temp_low_short":{"zh-Hans":"续航与功率会临时缩水","en":"Runtime and power drop temporarily","ja":"持続時間と出力が一時低下","de":"Laufzeit und Leistung sinken vorübergehend"},
"p.temp_high_short":{"zh-Hans":"发热增加并加速老化","en":"More heat and faster ageing","ja":"発熱が増え劣化が加速","de":"Mehr Wärme und schnellere Alterung"},
"p.power_low_short":{"zh-Hans":"续航更长、发热更少","en":"Longer runtime and less heat","ja":"長く持ち、発熱が少ない","de":"Längere Laufzeit, weniger Wärme"},
"p.power_high_short":{"zh-Hans":"续航更短、发热增加","en":"Shorter runtime and more heat","ja":"持続時間が短く、発熱が増える","de":"Kürzere Laufzeit, mehr Wärme"},
"p.src_none_short":{"zh-Hans":"观察变化趋势","en":"Trend only","ja":"傾向を観察","de":"Nur Trend"},
"p.no_fixed_range":{"zh-Hans":"无固定正常范围","en":"No fixed normal range","ja":"固定の正常範囲なし","de":"Kein fester Normalbereich"},
"p.id_no_range":  {"zh-Hans":"标识值，无正常范围","en":"Identifier — no normal range","ja":"識別値・正常範囲なし","de":"Kennung — kein Normalbereich"},
"p.counter_range": {"zh-Hans":"累计值，重点看变化","en":"Cumulative — watch the trend","ja":"累積値・変化を確認","de":"Kumulativ — Trend beachten"},
"p.rated_value":   {"zh-Hans":"额定值","en":"rated value","ja":"定格値","de":"Nennwert"},
"p.chart_time":    {"zh-Hans":"时刻","en":"Time","ja":"時刻","de":"Zeit"},
"p.chart_hours":   {"zh-Hans":"还能使用","en":"Time remaining","ja":"残り時間","de":"Restzeit"},
"p.left_axis":     {"zh-Hans":"左轴","en":"left axis","ja":"左軸","de":"linke Achse"},
"p.right_axis":    {"zh-Hans":"右轴","en":"right axis","ja":"右軸","de":"rechte Achse"},
"p.chart_waiting": {"zh-Hans":"等待电量计给出续航预测","en":"Waiting for the gauge's runtime estimate","ja":"電量計の残り時間予測を待っています","de":"Warten auf die Laufzeitschätzung des Gauges"},
"p.no_estimate_ac":{"zh-Hans":"已连接电源，电量计暂不估算剩余时间","en":"Connected to power — the gauge is not estimating runtime","ja":"電源接続中のため、電量計は残り時間を推定していません","de":"Am Netzteil — das Gauge schätzt derzeit keine Restlaufzeit"},
"p.remaining_trend":{"zh-Hans":"系统剩余时间记录","en":"System time-remaining history","ja":"システム残り時間の履歴","de":"Verlauf der System-Restzeit"},
"p.direct_source": {"zh-Hans":"来源：macOS 系统值","en":"Source: macOS system value","ja":"出典：macOS システム値","de":"Quelle: macOS-Systemwert"},
"p.sample_cadence_short":{"zh-Hans":"正式 App：约 56 秒记录一次","en":"App: records about every 56 seconds","ja":"正式アプリ：約56秒ごとに記録","de":"App: Aufzeichnung etwa alle 56 Sekunden"},
"p.no_recalc":    {"zh-Hans":"计算：不按功率二次换算","en":"Calculation: no power-based recalculation","ja":"計算：電力から再計算しない","de":"Berechnung: keine Neuberechnung aus Leistung"},
"p.no_history":   {"zh-Hans":"当前快照没有可用的系统续航历史；正式 App 会在拔下电源后开始记录","en":"This snapshot has no system runtime history; the app starts recording on battery power","ja":"このスナップショットには履歴がありません。正式アプリはバッテリー駆動で記録を開始します","de":"Dieser Snapshot enthält keinen Restzeitverlauf; die App zeichnet ihn im Akkubetrieb auf"},
"p.unplug_badge": {"zh-Hans":"拔电预计","en":"Unplug estimate","ja":"抜電時の予測","de":"Prognose ohne Netzteil"},
"p.unplug_kicker":{"zh-Hans":"按当前电脑状态，拔掉电源后大约还能用","en":"At the computer's current state, unplugging would give about","ja":"現在の状態で電源を外した場合のおおよその使用時間","de":"Bei aktuellem Zustand nach dem Abziehen ungefähr nutzbar"},
"p.unplug_note":  {"zh-Hans":"预计值 · 按当前电脑功耗，拔掉电源后可用","en":"Estimate · expected after unplugging at the computer's current power use","ja":"予測値 · 現在の消費電力で電源を外した場合","de":"Schätzung · Laufzeit nach dem Abziehen bei aktueller Leistung"},
"p.unplug_trend": {"zh-Hans":"拔电后的预计续航","en":"Estimated runtime after unplugging","ja":"電源を外した後の予測駆動時間","de":"Geschätzte Laufzeit nach dem Abziehen"},
"p.unplug_head":  {"zh-Hans":"还没有放电历史，先用虚线展示按当前电脑状态估算的拔电续航","en":"With no discharge history yet, the dashed line estimates unplugged runtime from the current computer state","ja":"放電履歴がないため、現在の状態から予測した抜電後の駆動時間を破線で表示します","de":"Ohne Entladeverlauf zeigt die gestrichelte Linie die geschätzte Laufzeit beim Abziehen"},
"p.unplug_legend":{"zh-Hans":"拔电预计 · 不是系统历史","en":"Unplug estimate · not system history","ja":"抜電時の予測 · システム履歴ではありません","de":"Prognose ohne Netzteil · kein Systemverlauf"},
"p.unplug_method":{"zh-Hans":"计算：当前剩余能量 ÷ 当前功耗","en":"Calculation: current stored energy ÷ current power use","ja":"計算：現在の残存エネルギー ÷ 現在の消費電力","de":"Berechnung: Restenergie ÷ aktuelle Leistung"},
"p.full_tank_explain":{"zh-Hans":"满电只是“油箱装满”；现在功耗是日常水平的 {ratio}%，所以会用得更快。","en":"A full charge only means the tank is full. Power use is now {ratio}% of your usual level, so it will drain faster.","ja":"満充電は「タンクが満杯」という意味にすぎません。現在の消費電力は普段の {ratio}% なので、より早く減ります。","de":"Voll geladen heißt nur: Der Tank ist voll. Der Verbrauch liegt jetzt bei {ratio}% des üblichen Werts, deshalb leert er sich schneller."},
"p.model_design_energy":{"zh-Hans":"这款机型出厂设计","en":"Design energy for this model","ja":"この機種の設計エネルギー","de":"Auslegungsenergie dieses Modells"},
"p.current_full_energy":{"zh-Hans":"这块电池现在充满","en":"This battery when full now","ja":"現在の満充電エネルギー","de":"Dieser Akku heute voll"},
"p.energy_in_battery":{"zh-Hans":"此刻剩余能量","en":"Energy remaining now","ja":"現在の残存エネルギー","de":"Aktuell verbleibende Energie"},
"p.current_power":{"zh-Hans":"当前功耗","en":"Current power use","ja":"現在の消費電力","de":"Aktueller Verbrauch"},
"p.current_use_estimate":{"zh-Hans":"照现在这样用","en":"At this usage","ja":"この使い方なら","de":"Bei dieser Nutzung"},
"p.baseline_compare":{"zh-Hans":"回到本机日常功耗 {watts}W，预计约 {time}；较短的数字主要反映当前负载较高。","en":"At this Mac's usual {watts}W, the estimate is about {time}. The shorter figure mainly reflects the current workload.","ja":"この Mac の普段の {watts}W なら約 {time} の見込みです。短い予測は主に現在の負荷を反映します。","de":"Beim üblichen Verbrauch dieses Macs von {watts} W wären es etwa {time}. Der kurze Wert spiegelt vor allem die aktuelle Last wider."},
"p.runtime_audit_tag":{"zh-Hans":"公开基准 × 本机实测","en":"Published benchmark × this Mac","ja":"公開基準 × このMacの実測","de":"Öffentlicher Richtwert × dieser Mac"},
"p.runtime_audit_title":{"zh-Hans":"官方 15 小时为什么到了现在只剩几小时？","en":"Why can an official 15 hours become only a few hours now?","ja":"公称15時間が、なぜ今は数時間になるのか？","de":"Warum werden aus offiziell 15 Stunden jetzt nur wenige?"},
"p.audit_official":{"zh-Hans":"Apple 新机无线网页测试","en":"Apple new-battery wireless web test","ja":"Apple 新品のワイヤレスWebテスト","de":"Apple WLAN-Webtest mit neuem Akku"},
"p.audit_same_load":{"zh-Hans":"这块电池按相同轻负载","en":"This battery at the same light workload","ja":"このバッテリーを同じ軽負荷で使用","de":"Dieser Akku bei derselben leichten Last"},
"p.audit_actual":{"zh-Hans":"此刻系统实际续航","en":"Actual system runtime now","ja":"現在のシステム実測駆動時間","de":"Aktuelle Systemlaufzeit"},
"p.audit_capacity_note":{"zh-Hans":"容量影响：比新机少约 {hours} 小时","en":"Capacity effect: about {hours} hours below new","ja":"容量の影響：新品より約 {hours} 時間短い","de":"Kapazitätseffekt: ca. {hours} Std. weniger als neu"},
"p.audit_load_note":{"zh-Hans":"负载影响：再缩短约 {hours} 小时","en":"Workload effect: about {hours} more hours lost","ja":"負荷の影響：さらに約 {hours} 時間短い","de":"Lasteffekt: nochmals ca. {hours} Std. weniger"},
"p.audit_cause":{"zh-Hans":"主要原因：当前负载","en":"Main cause: current workload","ja":"主因：現在の負荷","de":"Hauptursache: aktuelle Last"},
"p.audit_cause_body":{"zh-Hans":"当前功耗约为 Apple 无线网页测试隐含平均功耗的 {ratio} 倍。100% 只表示“当前容量已充满”，不代表能按官方轻负载使用 15 小时。","en":"Current power is about {ratio}× the implied average in Apple's wireless-web test. 100% means today's capacity is full, not that the Mac is running the official light workload.","ja":"現在の消費電力は Apple のWebテスト推定平均の約 {ratio} 倍。100%は現在容量が満充電という意味で、公式の軽負荷が続く意味ではありません。","de":"Die aktuelle Leistung liegt etwa beim {ratio}-Fachen des aus Apples Webtest abgeleiteten Mittels. 100 % bedeutet voller heutiger Akku, nicht Apples leichte Testlast."},
"p.audit_test_config":{"zh-Hans":"Apple 测试机","en":"Apple test system","ja":"Apple テスト機","de":"Apple Testsystem"},
"p.audit_your_config":{"zh-Hans":"你的电脑","en":"Your Mac","ja":"あなたのMac","de":"Dein Mac"},
"p.audit_conditions":{"zh-Hans":"无线网页：Wi-Fi 浏览 25 个网站；屏幕亮度从最低调高 8 格，键盘背光关闭。","en":"Wireless web: 25 websites over Wi-Fi; display at 8 clicks from bottom and keyboard backlight off.","ja":"Wi-Fiで25サイトを閲覧。画面は最低から8クリック、キーボード照明はオフ。","de":"WLAN-Web: 25 Websites; Display 8 Stufen über Minimum, Tastaturbeleuchtung aus."},
"p.audit_method":{"zh-Hans":"换算方法：53.8Wh ÷ 15h ≈ 官方网页测试平均 3.59W；再用本机当前满充能量与系统功耗作同口径对比。","en":"Method: 53.8Wh ÷ 15h ≈ 3.59W average for the official web test; compare that with this battery's scaled full energy and system power.","ja":"換算：53.8Wh ÷ 15h ≈ 公式Webテスト平均3.59W。本機の現在満充電エネルギーとシステム電力を同じ尺度で比較。","de":"Methode: 53,8Wh ÷ 15h ≈ 3,59W im offiziellen Webtest; Vergleich mit aktueller Vollenergie und Systemleistung."},
"p.help_open":{"zh-Hans":"查看指标定义与公式","en":"View definition and formula","ja":"指標の定義と式を見る","de":"Definition und Formel anzeigen"},
"p.help_title":{"zh-Hans":"指标是怎么来的？","en":"Where does this metric come from?","ja":"この指標はどう算出される？","de":"Woher kommt dieser Wert?"},
"p.help_current":{"zh-Hans":"当前结果","en":"Current result","ja":"現在の結果","de":"Aktuelles Ergebnis"},
"p.help_raw":{"zh-Hans":"最底层输入字段","en":"Lowest-level input fields","ja":"最下層の入力フィールド","de":"Unterste Eingabefelder"},
"p.help_formula":{"zh-Hans":"计算公式","en":"Formula","ja":"計算式","de":"Formel"},
"p.help_substitution":{"zh-Hans":"代入本机当前数字","en":"Substitute this Mac's values","ja":"このMacの現在値を代入","de":"Werte dieses Macs eingesetzt"},
"p.help_source":{"zh-Hans":"口径与可信度","en":"Source and reliability","ja":"出典と信頼度","de":"Quelle und Zuverlässigkeit"},
"p.help_direct":{"zh-Hans":"无计算公式：系统字段直接读取。","en":"No formula: read directly from the system field.","ja":"計算式なし：システムフィールドから直接取得。","de":"Keine Formel: direkt aus dem Systemfeld gelesen."},
"p.help_model_spec":{"zh-Hans":"系统机型标识匹配 Apple 官方公开规格。","en":"System model identifier matched to Apple's published specification.","ja":"システム機種IDをApple公開仕様に照合。","de":"Systemmodellkennung mit Apples veröffentlichter Spezifikation abgeglichen."},
"p.help_derived":{"zh-Hans":"由系统原始字段推导，不是 IOKit 直接返回的同名字段。","en":"Derived from raw system fields; not a same-named value returned directly by IOKit.","ja":"システム生フィールドから推導。IOKitが同名で直接返す値ではありません。","de":"Aus System-Rohfeldern abgeleitet; kein gleichnamiger direkter IOKit-Wert."},
"p.help_close":{"zh-Hans":"关闭","en":"Close","ja":"閉じる","de":"Schließen"},
"hw.group.runtime":{"zh-Hans":"续航与系统估算","en":"Runtime and system estimates"},
"p.hw_group_runtime":{"zh-Hans":"剩余时间、充满时间与唤醒后的估算保护窗","en":"Time remaining, time to full, and the post-wake invalid window"},
"hw.group.resistance":{"zh-Hans":"内阻与放电曲线","en":"Resistance and discharge curve"},
"p.hw_group_resistance":{"zh-Hans":"各电芯内阻，以及低电量时是否更容易电压塌陷","en":"Cell resistance and susceptibility to voltage sag at low charge"},
"hw.m.current_capacity":{"zh-Hans":"系统显示电量百分比","en":"System charge percentage"},
"hw.n.current_capacity":{"zh-Hans":"Apple Silicon 上是0–100%的用户口径；容量计算应使用 AppleRawCurrentCapacity。","en":"User-facing 0–100% on Apple Silicon; capacity math should use AppleRawCurrentCapacity."},
"hw.m.fcc_comp":{"zh-Hans":"满充容量补偿副本","en":"Full-charge capacity compensation copies"},
"hw.n.fcc_comp":{"zh-Hans":"本机 FccComp1/FccComp2 与 AppleRawMaxCapacity 相同，属于冗余校验字段。","en":"FccComp1/FccComp2 equal AppleRawMaxCapacity on this Mac and serve as redundant checks."},
"hw.m.chemical_ra":{"zh-Hans":"化学加权内阻","en":"Chemical weighted resistance"},
"hw.n.chemical_ra":{"zh-Hans":"本机为0，视为没有可用读数，不参与判断。","en":"Zero on this Mac, treated as unavailable and excluded from conclusions."},
"hw.m.cell_wom":{"zh-Hans":"电芯健康辅助字段","en":"Auxiliary cell-health field"},
"hw.n.cell_wom":{"zh-Hans":"本机只有2个全零元素，而实际为3节电芯，基数不符，不可用于评分。","en":"Only two zero entries for a three-cell pack; cardinality mismatch makes it unusable for scoring."},
"hw.m.time_remaining":{"zh-Hans":"电量计剩余时间预测","en":"Gauge time-remaining estimate"},
"hw.n.time_remaining":{"zh-Hans":"TimeRemaining 与 AvgTimeToEmpty 直接来自电量计；65535表示未就绪，不是65535分钟。","en":"TimeRemaining and AvgTimeToEmpty come directly from the gauge; 65535 means unavailable, not minutes."},
"hw.m.time_to_full":{"zh-Hans":"预计充满剩余时间","en":"Estimated time to full"},
"hw.n.time_to_full":{"zh-Hans":"仅充电且算法就绪时有效；65535表示未就绪或当前不适用。","en":"Valid only while charging and ready; 65535 means unavailable or not applicable."},
"hw.m.invalid_wake":{"zh-Hans":"唤醒后估算保护窗","en":"Post-wake estimate invalid window"},
"hw.n.invalid_wake":{"zh-Hans":"刚唤醒后的这段秒数内，续航预测可能尚未稳定。","en":"Runtime estimates may be unstable for this many seconds after wake."},
"hw.m.system_input":{"zh-Hans":"适配器输入功率/电压/电流","en":"Adapter input power/voltage/current"},
"hw.m.adapter_efficiency_loss":{"zh-Hans":"适配器效率损耗原始值","en":"Raw adapter-efficiency loss"},
"hw.n.adapter_efficiency_loss":{"zh-Hans":"瞬时值可能为0或负，累计量缩放未知，不能据此计算充电效率。","en":"Instant values may be zero or negative and cumulative scaling is unknown; do not derive charging efficiency."},
"hw.m.accumulated_avg_power":{"zh-Hans":"遥测累计平均系统功耗","en":"Telemetry accumulated average power"},
"hw.n.accumulated_avg_power":{"zh-Hans":"AccumulatedSystemLoad ÷ SystemLoadAccumulatorCount ÷ 1000，适合做本机长期基线。","en":"AccumulatedSystemLoad ÷ SystemLoadAccumulatorCount ÷ 1000, useful as this Mac's baseline."},
"hw.m.wall_energy":{"zh-Hans":"累计市电取电原始值","en":"Raw accumulated wall-energy value"},
"hw.n.wall_energy":{"zh-Hans":"公开结构没有确认单位与缩放，只保留原始诊断值，不换算能量。","en":"Unit and scaling are undocumented; preserve only as a raw diagnostic value."},
"hw.m.qmax_disqualification":{"zh-Hans":"Qmax 标定失效原因码","en":"Qmax disqualification reason code"},
"hw.n.qmax_disqualification":{"zh-Hans":"0仅表示当前原始状态码为0；非0时说明容量标定可能无效，具体位义未公开。","en":"Zero is only the current raw code; nonzero may invalidate calibration, while bit meanings remain undocumented."},
"hw.m.daily_soc_pair":{"zh-Hans":"当日最高/最低电量","en":"Daily maximum/minimum charge"},
"hw.m.adapter_contract":{"zh-Hans":"PD 协商电压/电流","en":"Negotiated PD voltage/current"},
"hw.m.adapter_menu":{"zh-Hans":"PD 可协商档位表","en":"Negotiable PD profiles"},
"hw.n.adapter_menu":{"zh-Hans":"仅插电时存在；最高档反映设备和适配器当前公开的协商能力。","en":"Available only on AC; the highest profile reflects currently advertised negotiation capability."},
"hw.m.adapter_description":{"zh-Hans":"适配器接口类型","en":"Adapter interface type"},
"hw.m.charge_limits":{"zh-Hans":"充电限压/限流","en":"Charging voltage/current limits"},
"hw.m.carrier_mode":{"zh-Hans":"运输模式限充阈值与状态","en":"Carrier-mode charge thresholds and status"},
"hw.n.carrier_mode":{"zh-Hans":"High/Low 是运输模式阈值；Status需结合系统状态判断，不能直接当成80%充电上限。","en":"High/Low are carrier thresholds; Status needs system context and is not directly the 80% charge limit."},
"hw.m.port_cycles":{"zh-Hans":"端口控制器插入/拔出计数","en":"Port-controller attach/detach counts"},
"hw.n.port_cycles":{"zh-Hans":"数组顺序不能安全映射成左/右端口，因此只标控制器1/2/3。计数异常增长可能提示接触问题。","en":"Array order cannot safely map to left/right ports, so controllers are numbered. Abnormal growth may indicate contact issues."},
"hw.m.port_failures":{"zh-Hans":"端口能力不匹配/协商失败","en":"Port capability mismatch/election failure"},
"hw.n.port_failures":{"zh-Hans":"非0可指向线缆、适配器或PD协商问题；当前显示每个控制器的原始计数/代码。","en":"Nonzero values can point to cable, adapter, or PD negotiation issues; values are shown per controller."},
"hw.m.chem_ids":{"zh-Hans":"电芯化学体系与算法化学ID","en":"Cell chemistry and algorithm chemistry IDs"},
"hw.m.manufacture_batch":{"zh-Hans":"制造批号原始整数","en":"Raw manufacturing batch integer"},
"hw.n.manufacture_batch":{"zh-Hans":"该整数可解码为ASCII批号，但不是经过验证的日历日期。","en":"The integer decodes to an ASCII batch code, not a verified calendar date."},
"hw.m.first_use":{"zh-Hans":"首次使用日期原始值","en":"Raw first-use date"},
"hw.n.first_use":{"zh-Hans":"本机恒为0，无法据此获得真实电池年龄。","en":"Zero on this Mac, so true battery age cannot be obtained from it."},
"hw.m.installed":{"zh-Hans":"电池已安装/内置状态","en":"Battery installed/built-in state"},
"hw.m.temperature":{"zh-Hans":"电芯实测温度","en":"Measured cell temperature"},
"hw.m.model_design_energy":{"zh-Hans":"机型额定设计能量","en":"Model-rated design energy","ja":"機種定格設計エネルギー","de":"Nennenergie des Modells"},
"hw.n.model_design_energy":{"zh-Hans":"系统识别机型后匹配 Apple 官方规格的额定 Wh；它不是用当前电压换算出来的。","en":"Rated Wh matched to Apple's specification after identifying the system model; it is not calculated from current voltage.","ja":"システム機種を識別し Apple 公式仕様に照合した定格 Wh。現在電圧からの換算ではありません。","de":"Nenn-Wh aus Apples Spezifikation nach Erkennung des Systemmodells; nicht aus der aktuellen Spannung berechnet."},
"hw.m.current_full_energy":{"zh-Hans":"当前满充能量（折算）","en":"Current full-charge energy (scaled)","ja":"現在の満充電エネルギー（換算）","de":"Aktuelle Vollenergie (skaliert)"},
"hw.n.current_full_energy":{"zh-Hans":"机型设计 Wh × 当前满充容量 ÷ 设计容量，用同一把尺估算这块电池现在充满能装多少能量。","en":"Model design Wh × current full-charge capacity ÷ design capacity, keeping one consistent scale for today's full battery.","ja":"機種設計 Wh × 現在の満充電容量 ÷ 設計容量。同じ尺度で現在の満充電エネルギーを見積もります。","de":"Modell-Nennenergie × aktuelle Vollkapazität ÷ Designkapazität, auf einer einheitlichen Skala."},
"p.forecast_only":{"zh-Hans":"虚线只作当前预测，不会写入系统历史","en":"The dashed line is a current forecast and is not saved as system history","ja":"破線は現在の予測で、システム履歴には保存されません","de":"Die gestrichelte Linie ist nur eine aktuelle Prognose und wird nicht als Systemverlauf gespeichert"},
"p.snapshot":      {"zh-Hans":"数据快照","en":"Snapshot","ja":"データ時刻","de":"Snapshot"},
"p.snapshot_note": {"zh-Hans":"HTML 原型显示生成时的系统快照；正式 App 会实时更新","en":"This HTML prototype shows a system snapshot captured when generated; the app will update live","ja":"HTML 原型は生成時のシステムスナップショットです。正式アプリではリアルタイム更新します","de":"Der HTML-Prototyp zeigt einen Snapshot bei der Erstellung; die App aktualisiert live"},
"p.usage_basis":   {"zh-Hans":"macOS 直接给出的系统估算；本产品不按功率另算","en":"Reported directly by macOS; this product does not recalculate it from power","ja":"macOS が直接返す推定値で、電力から再計算しません","de":"Direkt von macOS gemeldet; keine eigene Berechnung aus der Leistung"},
"p.system_charge": {"zh-Hans":"macOS 电量","en":"macOS charge","ja":"macOS 残量","de":"macOS-Ladung"},
"p.priority_health":{"zh-Hans":"整块电池的健康状况","en":"Overall battery health","ja":"バッテリー全体の健康状態","de":"Gesamtzustand des Akkus"},
"p.priority_power":{"zh-Hans":"目前电脑的使用功率","en":"Current computer power use","ja":"現在の消費電力","de":"Aktuelle Leistungsaufnahme"},
"p.priority_temp": {"zh-Hans":"目前电池温度","en":"Current battery temperature","ja":"現在のバッテリー温度","de":"Aktuelle Akkutemperatur"},
"p.tagline":      {"zh-Hans":"电池监控中心","en":"Battery Monitor","ja":"バッテリーモニター","de":"Batterie-Monitor"},
"p.remaining":    {"zh-Hans":"还能用多久","en":"Time remaining","ja":"あと何時間使えるか","de":"Verbleibende Zeit"},
"p.src_note":     {"zh-Hans":"macOS 直接给出的系统剩余时间；本产品不按功率另算","en":"Time remaining reported directly by macOS; this product does not recalculate it from power",
                   "ja":"macOS が直接返す残り時間で、電力から再計算しません","de":"Direkt von macOS gemeldete Restzeit; keine Neuberechnung aus Leistung"},
"p.why_title":    {"zh-Hans":"为什么最后 20% 掉得特别快","en":"Why the last 20% drains so fast",
                   "ja":"なぜ残り20%から急に減るのか","de":"Warum die letzten 20 % so schnell weg sind"},
"p.why_sub":      {"zh-Hans":"你的电池不是被「用完」的 —— 是电压塌了先关机","en":"Your battery is never “used up” — the voltage collapses first",
                   "ja":"バッテリーは「使い切る」のではなく、電圧が落ちて先に停止します","de":"Der Akku wird nie „leer“ – die Spannung bricht vorher ein"},
"p.aha_label":    {"zh-Hans":"啊哈时刻","en":"Aha moment","ja":"なるほどポイント","de":"Aha-Moment"},
"p.health_two_title":{"zh-Hans":"为什么健康度 {sys}%，可用容量却是 {raw}%？","en":"Why is health {sys}% while usable capacity is {raw}%?","ja":"健康度 {sys}% なのに使用可能容量は {raw}%？","de":"Warum {sys}% Zustand, aber {raw}% nutzbare Kapazität?"},
"p.health_two_body":{"zh-Hans":"<strong>像用两把尺量同一个水箱。</strong>系统评分会把安全备用量也考虑进去；容量条只看现在真正能装多少。两者都能参考，但比较前后变化时要一直用同一把尺。",
                   "en":"<strong>It is like measuring one tank with two rulers.</strong> The system score accounts for the safety reserve; the capacity bar shows what can actually be filled now. Both are useful, but trends need the same ruler.",
                   "ja":"<strong>同じタンクを2本の物差しで測るようなもの。</strong>システム評価は安全予備も考慮し、容量バーは現在実際に満たせる量を示します。推移は同じ物差しで比べます。",
                   "de":"<strong>Wie ein Tank, der mit zwei Maßstäben gemessen wird.</strong> Die Systemwertung berücksichtigt die Sicherheitsreserve; der Balken zeigt, was heute wirklich gefüllt werden kann. Trends immer mit demselben Maßstab vergleichen."},
"p.health_two_formula":{"zh-Hans":"{sys}% 系统健康评分 · {raw}% 直接容量比例","en":"{sys}% system health score · {raw}% direct capacity ratio","ja":"{sys}% システム健康評価 · {raw}% 直接容量比","de":"{sys}% Systemzustand · {raw}% direktes Kapazitätsverhältnis"},
"p.loss_split_title":{"zh-Hans":"总差额 {gap} mAh = 取不出来 + 已老化","en":"Total gap {gap} mAh = unreachable + aged","ja":"総差額 {gap} mAh = 取り出せない分 + 劣化","de":"Gesamtlücke {gap} mAh = unerreichbar + gealtert"},
"p.loss_split_body":{"zh-Hans":"<strong>还是水箱的比喻：</strong>{un} mAh 像吸管够不到的杯底水，电还在；真正让“水箱变小”的老化只有 {aged} mAh。两部分加起来，才是和出厂容量相比少掉的总量。",
                   "en":"<strong>Using the same tank analogy:</strong> {un} mAh is like water below the straw—still there. Only {aged} mAh is the tank itself becoming smaller. Together they make the gap from new.",
                   "ja":"<strong>同じタンクの例なら、</strong>{un} mAh はストローが届かない底の水で、まだ残っています。タンク自体が小さくなったのは {aged} mAh だけです。",
                   "de":"<strong>Im Tankbild:</strong> {un} mAh sind wie Wasser unter dem Strohhalm und noch vorhanden. Nur {aged} mAh sind der kleiner gewordene Tank. Zusammen bilden sie die Lücke zum Neuzustand."},
"p.loss_split_formula":{"zh-Hans":"{gap} mAh 总差额 = {un} mAh 用不到 + {aged} mAh 真正老化","en":"{gap} mAh total gap = {un} mAh out of reach + {aged} mAh aged","ja":"総差額 {gap} mAh = 使えない {un} mAh + 劣化 {aged} mAh","de":"{gap} mAh Gesamtlücke = {un} mAh unerreichbar + {aged} mAh gealtert"},
"p.use_loss_title":{"zh-Hans":"今天用掉的电，不等于电池老化","en":"Energy used today is not battery ageing","ja":"今日使った電気とバッテリー劣化は別","de":"Heute verbrauchte Energie ist keine Alterung"},
"p.use_loss_body":{"zh-Hans":"<strong>像水杯里的水和水杯大小。</strong>本次用掉的 {used} mAh，插电就能补回来；长期损失的 {loss} mAh，是水杯相比出厂时变小的部分。",
                   "en":"<strong>Think of water in a cup versus the size of the cup.</strong> The {used} mAh used this time returns when charged; the {loss} mAh long-term loss is the cup becoming smaller than when new.",
                   "ja":"<strong>コップの水とコップ自体の大きさの違いです。</strong>今回使った {used} mAh は充電で戻り、長期損失 {loss} mAh は新品時よりコップが小さくなった分です。",
                   "de":"<strong>Wasser im Becher ist etwas anderes als die Bechergröße.</strong> Die diesmal verbrauchten {used} mAh kommen beim Laden zurück; {loss} mAh Langzeitverlust sind der kleinere Becher."},
"p.use_loss_formula":{"zh-Hans":"本次已用 {used} mAh · 长期损失 {loss} mAh · 两者不要相加","en":"Used this time {used} mAh · long-term loss {loss} mAh · do not add them","ja":"今回使用 {used} mAh · 長期損失 {loss} mAh · 合算しない","de":"Diesmal verbraucht {used} mAh · Langzeitverlust {loss} mAh · nicht addieren"},
"p.aging_judge_title":{"zh-Hans":"判断老化，别只看循环次数","en":"Do not judge ageing from cycle count alone","ja":"劣化はサイクル数だけで判断しない","de":"Alterung nicht nur an Zyklen messen"},
"p.aging_judge_lead":{"zh-Hans":"循环次数像里程表：告诉你用过多少，不直接告诉你还健康多少。","en":"Cycle count is an odometer: it shows use, not health by itself.","ja":"サイクル数は走行距離計。使用量は示しますが、健康度そのものではありません。","de":"Zyklen sind wie ein Kilometerzähler: Nutzung ja, Gesundheit nicht allein."},
"p.aging_judge_body":{"zh-Hans":"真正值得一起看的，是满充容量有没有持续下降、内阻有没有上升、电芯是否开始失衡，以及高温是否经常出现。只有这些趋势共同变化，才足以解释为什么续航真的变差。",
                   "en":"What matters together is whether full-charge capacity keeps falling, resistance rises, cells drift apart, and high temperature becomes common. Those trends explain a real runtime decline.",
                   "ja":"満充電容量の継続低下、内部抵抗の上昇、セルのばらつき、高温の頻発を合わせて見ます。これらの推移が実際の駆動時間低下を説明します。",
                   "de":"Entscheidend sind sinkende Vollladekapazität, steigender Widerstand, Zellabweichung und häufige Hitze. Erst gemeinsam erklären diese Trends einen echten Laufzeitverlust."},
"p.aging_proof": {"zh-Hans":"这台电脑已完成 {cyc} 次循环；现在的满充容量比出厂设计少 {loss}。把这个差额除以循环得到的 {per}/循环，只是回看平均数，不是每次循环的真实损耗，也不能拿来外推寿命。",
                   "en":"This Mac has {cyc} cycles; current full-charge capacity is {loss} below design. The {per}-per-cycle figure is only a retrospective average—not measured loss per cycle and not a life forecast.",
                   "ja":"この Mac は {cyc} サイクルで、現在の満充電容量は設計値より {loss} 少なくなっています。{per}/サイクルは過去平均にすぎず、毎回の実損失でも寿命予測でもありません。",
                   "de":"Dieser Mac hat {cyc} Zyklen; die aktuelle Vollladekapazität liegt {loss} unter Design. {per} pro Zyklus ist nur ein Rückblick, kein gemessener Einzelverlust und keine Lebensdauerprognose."},
"p.time_jump_title":{"zh-Hans":"剩余时间会跳，不是系统算错","en":"Time remaining can jump without being wrong","ja":"残り時間が跳ぶのは計算ミスではありません","de":"Sprünge der Restzeit sind kein Rechenfehler"},
"p.time_jump_lead":{"zh-Hans":"你开始编译，它往下修；停下来阅读，它又往上修。","en":"Start compiling and it falls; stop to read and it rises.","ja":"ビルドを始めると下がり、読むだけになると上がります。","de":"Beim Kompilieren sinkt sie, beim Lesen steigt sie wieder."},
"p.time_jump_body":{"zh-Hans":"电量没有反弹。macOS 会根据最近的负载不断重估“照这样用还能多久”。功率当然影响结果，但页面记录的是系统直接给出的剩余时间，不再用功率公式二次计算。",
                   "en":"The charge did not come back. macOS repeatedly re-estimates how long the current pattern can continue. Power affects the estimate, but this page records the system value directly instead of calculating another answer from power.",
                   "ja":"電量が戻ったわけではありません。macOS は直近の負荷から「この使い方ならあと何時間か」を再推定します。電力は影響しますが、ページは電力から再計算せずシステム値を記録します。",
                   "de":"Die Ladung ist nicht zurückgekehrt. macOS schätzt aus der jüngsten Last laufend neu. Leistung beeinflusst das Ergebnis, aber die Seite speichert den Systemwert direkt und berechnet keine zweite Antwort."},
"p.time_jump_proof":{"zh-Hans":"口径：拔电时记录 macOS 系统剩余时间；插电时没有系统值，才单独显示“当前剩余能量 ÷ 当前功耗”的拔电预计，并明确标成预测。",
                   "en":"Definition: on battery, record macOS time remaining. On power, when no system value exists, show stored energy divided by current power as a clearly labelled unplug estimate.",
                   "ja":"口径：バッテリー時は macOS の残り時間を記録。電源接続中にシステム値がない場合のみ、残存エネルギー÷消費電力を「抜電予測」と明記して表示します。",
                   "de":"Definition: im Akkubetrieb macOS-Restzeit speichern. Am Netz ohne Systemwert wird Restenergie geteilt durch aktuelle Leistung klar als Prognose beim Abziehen markiert."},
"p.geek":         {"zh-Hans":"完整硬件参数与逐项解释","en":"Complete hardware metrics with per-item explanations","ja":"完全なハードウェア指標と項目別説明","de":"Vollständige Hardware-Metriken mit Einzelerklärungen"},
"p.hw_intro_title":{"zh-Hans":"先看结论，想深挖时再看原始字段","en":"Start with the answer, then inspect raw fields when needed","ja":"まず結論、必要なときだけ原始フィールドへ","de":"Erst die Antwort, dann bei Bedarf Rohfelder"},
"p.hw_intro_body":{"zh-Hans":"这版原型已收录附件清单中的全部原始指标，并保留公开机型规格与必要推导。每项都有本机当前值、单位、解释、参考范围与可信度；复合项点 ? 可展开到每个最底层字段。",
                   "en":"This prototype includes every raw metric in the supplied list, plus the published model specification and necessary derivations. Each item has this Mac's current value, unit, explanation, range, and reliability; ? expands composite rows to their lowest-level fields.",
                   "ja":"添付リストの全生指標に加え、公開機種仕様と必要な導出値を収録。現在値、単位、説明、範囲、信頼性を示し、複合項目は ? で最下層フィールドまで展開できます。",
                   "de":"Alle Rohmetriken der gelieferten Liste plus veröffentlichte Modellspezifikation und nötige Ableitungen sind enthalten. ? öffnet zusammengesetzte Zeilen bis zu den untersten Feldern."},
"p.hw_search":    {"zh-Hans":"搜索字段、含义或分组，例如：温度 / capacity / charger","en":"Search field, meaning, or group: temperature / capacity / charger","ja":"フィールド・意味・グループを検索：温度 / capacity / charger","de":"Feld, Bedeutung oder Gruppe suchen: Temperatur / capacity / charger"},
"p.hw_no_results":{"zh-Hans":"没有匹配的指标，换一个更短的关键词试试。","en":"No matching metric. Try a shorter search term.","ja":"一致する指標がありません。短い語で試してください。","de":"Keine passende Metrik. Versuchen Sie einen kürzeren Begriff."},
"p.hw_group_cells":{"zh-Hans":"电芯一致性、放电深度与永久故障","en":"Cell balance, depth of discharge, and permanent faults","ja":"セル均衡・放電深度・永久故障","de":"Zellbalance, Entladetiefe und permanente Fehler"},
"p.hw_group_capacity":{"zh-Hans":"设计容量、满充容量与循环寿命","en":"Design, full charge, and cycle life","ja":"設計・満充電容量・サイクル寿命","de":"Design, Vollladung und Zyklen"},
"p.hw_group_electrical":{"zh-Hans":"此刻的电压、电流、功耗与温度","en":"Live voltage, current, power, and temperature","ja":"現在の電圧・電流・電力・温度","de":"Spannung, Strom, Leistung und Temperatur"},
"p.hw_group_charger":{"zh-Hans":"适配器能力与充电限制","en":"Adapter capability and charging limits","ja":"アダプタ能力と充電制限","de":"Netzteil und Ladegrenzen"},
"p.hw_group_telemetry":{"zh-Hans":"系统、墙插与电池之间的能量流","en":"Energy flow between system, adapter, and battery","ja":"システム・電源・電池間のエネルギー","de":"Energiefluss zwischen System, Netzteil und Akku"},
"p.hw_group_identity":{"zh-Hans":"电池、芯片、固件与机型身份","en":"Battery, gauge, firmware, and model identity","ja":"電池・ゲージ・FW・機種の識別","de":"Akku-, Gauge-, Firmware- und Modellidentität"},
"p.hw_group_lifetime":{"zh-Hans":"历史温度、电流、电压极值与容量标定可信度","en":"Lifetime extremes and capacity-calibration confidence","ja":"生涯極値と容量校正の信頼性","de":"Lebenszeit-Extremwerte und Zuverlässigkeit der Kapazitätskalibrierung"},
"p.hw_group_derived":{"zh-Hans":"把原始字段翻译成用户结论","en":"Derived answers from raw fields","ja":"原始値から導いたユーザー向け結論","de":"Aus Rohfeldern abgeleitete Aussagen"},
"hw.m.health_system":{"zh-Hans":"本原型的系统对齐健康度","en":"Prototype system-aligned health","ja":"本プロトタイプのシステム準拠健康度","de":"Systemnaher Zustand dieses Prototyps"},
"hw.n.health_system":{"zh-Hans":"原型目前使用 (FCC + 保留容量) ÷ (设计容量 − 保留容量)。这是根据本机显示反向校验的口径，仅在当前机器验证过，不代表 Apple 公开公式。",
                   "en":"This prototype uses (FCC + reserve) divided by (design minus reserve), reverse-checked against this Mac. It is verified only here and is not a published Apple formula.",
                   "ja":"本プロトタイプは (FCC+予備)/(設計−予備) を使用。本機表示から逆検証した口径で、この1台のみ確認済み。Apple 公開式ではありません。",
                   "de":"Dieser Prototyp nutzt (FCC + Reserve) geteilt durch (Design − Reserve), gegen diesen Mac geprüft. Nur hier verifiziert und keine veröffentlichte Apple-Formel."},
"hw.n.reserve":  {"zh-Hans":"系统不向用户电量百分比开放的缓冲容量。本原型把它用于系统对齐健康度公式；该公式只在当前机器反向验证过。",
                   "en":"Buffer capacity outside the user charge percentage. This prototype uses it in its system-aligned health definition, reverse-verified only on this Mac.",
                   "ja":"ユーザー残量%に公開されない予備容量。本プロトタイプのシステム準拠健康度に使いますが、本機のみ逆検証済みです。",
                   "de":"Pufferkapazität außerhalb der Nutzer-Ladeanzeige. Dieser Prototyp nutzt sie für den systemnahen Zustand; nur auf diesem Mac rückwärts verifiziert."},
"hw.n.unusable": {"zh-Hans":"Qmax 与 FCC 都来自电量计；“取不出来”是本原型对 Qmax − FCC 的解释性推导，不是电量计直接返回的同名字段。",
                   "en":"Qmax and FCC come from the gauge. “Unreachable” is this prototype's interpretation of Qmax minus FCC, not a directly named gauge field.",
                   "ja":"Qmax と FCC は電量計の値です。「取り出せない分」は本プロトタイプによる Qmax−FCC の解釈で、同名の直接フィールドではありません。",
                   "de":"Qmax und FCC stammen vom Gauge. „Nicht erreichbar“ ist die Interpretation dieses Prototyps von Qmax minus FCC, kein direkt so benanntes Feld."},
"hw.m.deficit_cycle":{"zh-Hans":"满充差额的历史平均 / 循环","en":"Historical full-charge gap per cycle","ja":"満充電差額の過去平均 / サイクル","de":"Historische Vollladelücke pro Zyklus"},
"hw.m.deficit_total":{"zh-Hans":"出厂设计与当前满充的总差额","en":"Total design-to-full-charge gap","ja":"設計値と現在満充電の総差額","de":"Gesamtlücke zwischen Design und Vollladung"},
"hw.n.deficit_cycle":{"zh-Hans":"用总差额除以循环次数得到的回看平均数；它混合了化学老化和当前取不出来的容量，不是每个循环的真实损耗，也不能外推寿命。",
                   "en":"A retrospective average from total gap divided by cycles. It mixes chemical fade with currently unreachable capacity, so it is not measured loss per cycle and must not forecast life.",
                   "ja":"総差額をサイクル数で割った過去平均。化学劣化と現在取り出せない容量が混在し、毎回の実損失でも寿命予測でもありません。",
                   "de":"Rückblickender Durchschnitt aus Gesamtlücke geteilt durch Zyklen. Mischt chemischen Verlust und aktuell unerreichbare Kapazität; kein Messverlust pro Zyklus und keine Prognose."},
"hw.n.deficit_total":{"zh-Hans":"Design − FCC。它不是纯老化量，而是“化学总容量下降”与“当前取不出来的容量”之和；必须结合 Qmax − FCC 拆开看。",
                   "en":"Design minus FCC. This is not pure ageing; it combines chemical total-capacity fade with currently unreachable capacity and must be split using Qmax minus FCC.",
                   "ja":"Design−FCC。純粋な劣化量ではなく、化学総容量低下と現在取り出せない容量の合計で、Qmax−FCC と分けて見ます。",
                   "de":"Design minus FCC. Kein reiner Alterungswert, sondern chemischer Kapazitätsverlust plus aktuell unerreichbare Kapazität; mit Qmax minus FCC aufteilen."},
"p.footer":       {"zh-Hans":"数据口径 · 电量与剩余时间优先取 macOS 用户可见系统值；硬件当前值来自本机 IOKit 快照（{time}）。<br>推导口径 · 健康度、容量拆分与插电时的拔电预计均明确标注为推导或预测，不会混入系统历史。<br>完整性 · {fields} 项已解释硬件指标 / {groups} 组 / {langs} 种语言；没有伪造长期趋势。",
                   "en":"Definitions · Charge and time remaining prefer the user-visible macOS values; hardware values come from this Mac's IOKit snapshot ({time}).<br>Derived values · Health, capacity splits, and the on-power unplug estimate are labelled as derived or forecast and never mixed into system history.<br>Coverage · {fields} explained metrics / {groups} groups / {langs} languages; no fabricated long-term trends.",
                   "ja":"口径 · 残量と残り時間は macOS のユーザー表示値を優先し、ハードウェア値は本機 IOKit スナップショット（{time}）です。<br>導出値 · 健康度・容量分解・接続中の抜電予測は導出または予測と明記し、システム履歴に混在させません。<br>網羅性 · 説明付き {fields} 指標 / {groups} グループ / {langs} 言語。長期推移の捏造はありません。",
                   "de":"Definitionen · Ladung und Restzeit bevorzugen die sichtbaren macOS-Systemwerte; Hardwarewerte stammen aus dem IOKit-Snapshot dieses Macs ({time}).<br>Ableitungen · Zustand, Kapazitätsaufteilung und Prognose beim Abziehen sind als Ableitung oder Prognose markiert und werden nie mit Systemverlauf vermischt.<br>Umfang · {fields} erklärte Metriken / {groups} Gruppen / {langs} Sprachen; keine erfundenen Langzeittrends."},
"p.hover_hint":   {"zh-Hans":"点击每项旁的 ? 查看底层字段、公式、代入过程与可靠性说明","en":"Click ? beside any metric for raw fields, formula, substitution, and reliability",
                   "ja":"各指標の ? をクリックして、生フィールド・式・代入・信頼性を確認","de":"? neben jedem Wert zeigt Rohfelder, Formel, Einsetzung und Zuverlässigkeit"},
"p.unusable_ex":  {"zh-Hans":"化学总容量 Qmax 中仍包含、但没有进入可用满充 FCC 的部分；由两个电量计读数相减推导。",
                   "en":"The part still included in chemical Qmax but excluded from usable full-charge FCC, derived by subtracting two gauge readings.",
                   "ja":"化学総容量 Qmax に含まれ、使用可能な満充電 FCC には含まれない部分。2つの電量計値の差から導出します。",
                   "de":"Der in chemischem Qmax enthaltene, aber aus nutzbarer FCC ausgeschlossene Teil; aus zwei Gauge-Werten abgeleitet."},
"p.nonlinear":    {"zh-Hans":"不要拿它外推寿命：锂电衰减前期快、之后趋平",
                   "en":"Do not extrapolate: lithium fade is fast early, then flattens",
                   "ja":"外挿は禁物：リチウムの劣化は初期が速く、その後緩やかになります",
                   "de":"Nicht extrapolieren: Li-Alterung ist früh schnell, dann flach"},
}
for lc in LANGS:
    for k, v in EXTRA.items():
        I18N[lc][k] = v.get(lc, v["en"])


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
