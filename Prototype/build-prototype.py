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
"p.dual_head":    {"zh-Hans":"功率一跳，剩余时间必然跟着动 —— 画在同一张图上","en":"Power moves, time-left follows — same chart",
                   "ja":"電力が動けば残り時間も動く —— 同じグラフで","de":"Leistung springt, Restzeit folgt — in einem Chart"},
"p.split_v":      {"zh-Hans":"电压 · 电池给的","en":"Voltage · what the cells give","ja":"電圧 · セル side","de":"Spannung · von den Zellen"},
"p.split_i":      {"zh-Hans":"电流 · 系统要的","en":"Current · what the system draws","ja":"電流 · システムの要求","de":"Strom · was das System zieht"},
"p.split_note":   {"zh-Hans":"电压由电池化学和剩余电量决定，你改不了，而且变化很慢；<b>能被你影响的只有电流</b>——关掉高占用进程、调低亮度，减的都是电流那一项。所以「省电」在物理上就等于「压低电流」。",
                   "en":"Voltage is set by cell chemistry and charge level — slow-moving and outside your control. <b>Only the current is yours to change</b>: closing heavy processes or dimming the display cuts the current term. Saving power physically means pulling less current.",
                   "ja":"電圧はセルの化学と残量で決まり、ゆっくりとしか変わらず制御できません。<b>変えられるのは電流だけ</b>——重いプロセスを閉じる、輝度を下げる、いずれも電流を減らす操作です。省電力とは物理的に「電流を抑えること」です。",
                   "de":"Die Spannung ergibt sich aus Zellchemie und Ladezustand — träge und nicht beeinflussbar. <b>Nur den Strom haben Sie in der Hand</b>: Prozesse schließen oder Helligkeit senken reduziert den Stromterm. Energiesparen heißt physikalisch: weniger Strom ziehen."},
"p.read_title":   {"zh-Hans":"这两个数是高是低？","en":"Are these numbers high or low?","ja":"この数値は高い？低い？","de":"Sind diese Werte hoch oder niedrig?"},
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
            peakW=round(abs(LT['MaximumDischargeCurrent'])*volt/1000), wh=round(fcc*volt/1000,1), tempAvg=round(LT['AverageTemperature']/10,1),
            tempMax=LT['MaximumTemperature'], tempMin=LT['MinimumTemperature'],
            model=subprocess.run(['sysctl','-n','hw.model'],capture_output=True,text=True).stdout.strip(),
            specs=SPECS, table=TABLE, i18n=I18N, langs=LANGS)

tpl = open(f"{ROOT}/Prototype/_template.html", encoding='utf-8').read()
out = tpl.replace("/*__DATA__*/", "const D = " + json.dumps(DATA, ensure_ascii=False) + ";")
dst = f"{ROOT}/Prototype/battery-final.html"
open(dst, 'w', encoding='utf-8').write(out)
print(f"已生成 {dst}  ({len(out):,} bytes)")
print(f"  真机数据：健康 {health_sys:.1f}% / 循环 {cyc} / 取不出来 {unusable}mAh / 每循环扣押 {deficit_pc:.1f}mAh")
print(f"  语言：{len(LANGS)} 种，译文取自 app 的语言包")
print(f"  硬件表：{sum(len(r) for _, r in TABLE)} 行 / {len(TABLE)} 组")
