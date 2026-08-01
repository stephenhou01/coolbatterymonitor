#!/usr/bin/env python3
"""Merge the finalized prototype copy into the app's JSON language packs.

The HTML prototype owns a small ``EXTRA`` dictionary for narrative copy that did
not exist in the original Swift app.  Keeping a tiny synchronizer avoids a
second hand-maintained copy while the prototype is being migrated to SwiftUI.
Languages not explicitly translated by the prototype intentionally use English,
matching the prototype's existing fallback behaviour.
"""

from __future__ import annotations

import ast
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROTOTYPE = ROOT / "Prototype" / "build-prototype.py"
LANGUAGE_DIR = ROOT / "Localization" / "Languages"

# Native-only labels added while turning the prototype table into an interactive
# SwiftUI evidence table.  The same four-language coverage/fallback policy as
# the prototype applies here.
APP_EXTRA = {
    "p.menu_language": {"zh-Hans": "语言", "en": "Language", "ja": "言語", "de": "Sprache"},
    "p.menu_quit": {
        "zh-Hans": "退出 BatteryMonitor", "en": "Quit BatteryMonitor",
        "ja": "BatteryMonitor を終了", "de": "BatteryMonitor beenden"
    },
    "p.power_center_title": {"zh-Hans": "当前功耗与程序活动", "en": "Live power and app activity"},
    "p.power_center_subtitle": {
        "zh-Hans": "蓝线是整台电脑的实时功率；右侧进程只解释当时谁更活跃，不把 CPU 占用伪装成精确瓦数。",
        "en": "The blue line is whole-computer power. Processes explain what was active without pretending CPU usage is exact per-process wattage."
    },
    "p.live_10s": {"zh-Hans": "每 10 秒", "en": "Every 10 seconds"},
    "p.live_paused": {"zh-Hans": "已暂停", "en": "Paused"},
    "p.pause_refresh": {"zh-Hans": "暂停", "en": "Pause"},
    "p.resume_refresh": {"zh-Hans": "继续", "en": "Resume"},
    "p.refresh_now": {"zh-Hans": "立即刷新", "en": "Refresh now"},
    "p.current_power_short": {"zh-Hans": "当前", "en": "Current"},
    "p.window_average": {"zh-Hans": "窗口均值", "en": "Window average"},
    "p.window_peak": {"zh-Hans": "窗口峰值", "en": "Window peak"},
    "p.power_collecting": {"zh-Hans": "正在收集实时功率；20 秒后会出现折线", "en": "Collecting live power; the line appears after 20 seconds"},
    "p.power_axis_time": {"zh-Hans": "横轴：时间", "en": "X-axis: time"},
    "p.power_axis_watts": {"zh-Hans": "纵轴：整机功率（W）", "en": "Y-axis: whole-computer power (W)"},
    "p.power_hover_hint": {"zh-Hans": "悬停查看每个时刻", "en": "Hover to inspect each moment"},
    "p.active_processes": {"zh-Hans": "此刻活跃的程序与进程", "en": "Active apps and processes"},
    "p.no_active_processes": {"zh-Hans": "当前没有达到展示门槛的活跃进程", "en": "No process currently reaches the display threshold"},
    "p.process_collecting": {"zh-Hans": "正在读取进程活动…", "en": "Reading process activity…"},
    "p.process_context_note": {
        "zh-Hans": "为什么不显示每个程序多少瓦？macOS 这里没有给出可靠的进程级瓦数；CPU% 只能帮助解释负载组合，不能直接分摊整机功耗。",
        "en": "Why not show watts per app? macOS does not expose reliable process-level wattage here; CPU% explains workload context but cannot split whole-computer power."
    },
    "p.system_data_title": {"zh-Hans": "所有系统数据 · 四层核验台", "en": "All system data · four-layer verifier"},
    "p.system_data_source": {"zh-Hans": "实时读取 macOS；Excel 仅提供字段含义，不提供页面数值", "en": "Live from macOS; Excel supplies field metadata, never displayed values"},
    "p.system_data_available": {"zh-Hans": "本次有值", "en": "Available now"},
    "p.system_data_anomaly": {"zh-Hans": "需关注", "en": "Needs attention"},
    "p.system_data_description": {
        "zh-Hans": "默认只显示能帮助判断续航、健康、功耗和温度的字段。切到异常可一键筛查；切到任一数据源或全部，可逐项对照上面的结论。Apple 未公开的内部字段会明确标为诊断项，不给它编造标准答案。",
        "en": "The default view keeps fields useful for runtime, health, power and temperature. Use Anomalies for one-click screening, or a source/all tab to verify the conclusions above. Undocumented Apple internals stay explicitly diagnostic."
    },
    "p.system_data_search": {"zh-Hans": "搜索字段、当前值、含义或说明", "en": "Search field, live value, meaning or note"},
    "p.system_data_field": {"zh-Hans": "字段路径", "en": "Field path"},
    "p.system_data_value": {"zh-Hans": "系统实测值", "en": "Live system value"},
    "p.system_data_unit": {"zh-Hans": "单位", "en": "Unit"},
    "p.system_data_meaning": {"zh-Hans": "这个数字说明什么", "en": "What it means"},
    "p.system_data_group": {"zh-Hans": "分组", "en": "Group"},
    "p.system_data_reliability": {"zh-Hans": "来源可靠性", "en": "Source reliability"},
    "p.system_data_value_level": {"zh-Hans": "价值", "en": "Value"},
    "p.system_tab_meaningful": {"zh-Hans": "有意义", "en": "Meaningful"},
    "p.system_tab_anomaly": {"zh-Hans": "异常", "en": "Anomalies"},
    "p.system_tab_all": {"zh-Hans": "全部展开", "en": "Show all"},
    "p.system_no_anomaly": {"zh-Hans": "本次快照没有命中已定义的异常规则", "en": "This snapshot matches none of the defined anomaly rules"},
    "p.system_no_results": {"zh-Hans": "没有匹配的系统字段", "en": "No matching system fields"},
    "p.system_data_unavailable": {"zh-Hans": "本次快照系统没有返回这个字段。", "en": "macOS did not return this field in the current snapshot."},
    "hw.column.product_value": {
        "zh-Hans": "产品价值", "en": "Product value", "ja": "製品価値", "de": "Produktwert"
    },
    "hw.column.usage": {
        "zh-Hans": "当前用途", "en": "Current use", "ja": "現在の用途", "de": "Aktuelle Nutzung"
    },
    "hw.column.value": {
        "zh-Hans": "价值", "en": "Value", "ja": "価値", "de": "Wert"
    },
    "hw.usage.primary": {
        "zh-Hans": "核心展示", "en": "Primary", "ja": "主要表示", "de": "Primär"
    },
    "hw.usage.calculation": {
        "zh-Hans": "参与计算", "en": "Calculated", "ja": "計算に使用", "de": "Berechnung"
    },
    "hw.usage.diagnosis": {
        "zh-Hans": "诊断依据", "en": "Diagnostic", "ja": "診断根拠", "de": "Diagnose"
    },
    "hw.usage.table": {
        "zh-Hans": "底表展示", "en": "Table only", "ja": "表のみ", "de": "Nur Tabelle"
    },
    "hw.usage.guarded": {
        "zh-Hans": "仅作参考", "en": "Reference", "ja": "参考のみ", "de": "Referenz"
    },
    "hw.usage.unused": {
        "zh-Hans": "不用于结论", "en": "Not used", "ja": "結論に不使用", "de": "Nicht verwendet"
    },
    "hw.m.max_capacity_raw": {
        "zh-Hans": "平台相关的 MaxCapacity 原始值", "en": "Platform-specific raw MaxCapacity",
        "ja": "プラットフォーム依存の MaxCapacity 生値", "de": "Plattformspezifischer MaxCapacity-Rohwert"
    },
    "hw.n.max_capacity_raw": {
        "zh-Hans": "Apple Silicon 上常为百分比，Intel 上也可能是 mAh；不能不看平台就直接参与容量计算。",
        "en": "Often a percentage on Apple silicon but may be mAh on Intel; never use it in capacity math without checking the platform.",
        "ja": "Apple Silicon では通常パーセント、Intel では mAh の場合があります。プラットフォーム確認なしに容量計算へ使えません。",
        "de": "Auf Apple Silicon meist Prozent, auf Intel teils mAh; nie ohne Plattformprüfung in Kapazitätsberechnungen verwenden."
    },
    "hw.m.ra_curve": {
        "zh-Hans": "15 点内阻—放电深度曲线", "en": "15-point resistance versus depth-of-discharge curve",
        "ja": "15点の内部抵抗―放電深度曲線", "de": "15-Punkt-Kurve Innenwiderstand gegen Entladetiefe"
    },
    "hw.n.ra_curve": {
        "zh-Hans": "用于解释低电量时的电压塌陷；中段趋势更可信，首尾端点需防止被噪声误导。",
        "en": "Explains low-charge voltage sag; the middle trend is more trustworthy and the end points need noise-aware interpretation.",
        "ja": "低残量時の電圧降下を説明します。中間域の傾向がより信頼でき、両端点はノイズを考慮します。",
        "de": "Erklärt Spannungseinbruch bei niedrigem Ladestand; der Mittelbereich ist verlässlicher, Endpunkte sind rauschanfällig."
    },
    "hw.m.last_qmax_cycle": {
        "zh-Hans": "上次成功容量标定时的循环数", "en": "Cycle count at the last successful Qmax calibration",
        "ja": "前回 Qmax 校正成功時のサイクル数", "de": "Zyklenzahl bei der letzten erfolgreichen Qmax-Kalibrierung"
    },
    "hw.n.last_qmax_cycle": {
        "zh-Hans": "当前循环数减去它，可以判断健康度读数距上次容量学习有多久。",
        "en": "Subtract it from the current cycle count to see how old the latest capacity learning is.",
        "ja": "現在のサイクル数との差で、最新の容量学習からの経過を判断できます。",
        "de": "Die Differenz zur aktuellen Zyklenzahl zeigt das Alter der letzten Kapazitätslernung."
    },
    "hw.n.nominal_relation": {
        "zh-Hans": "用于与满充容量和系统预留量交叉核验，不直接参与主界面健康度公式。",
        "en": "Cross-checks full-charge capacity plus system reserve; it is not a direct input to the headline health formula.",
        "ja": "満充電容量とシステム予約量の照合用で、主要な健康度式へ直接は使いません。",
        "de": "Dient zur Gegenprüfung von Vollladekapazität plus Systemreserve und fließt nicht direkt in die Hauptformel ein."
    },
    "hw.n.used_since_full": {
        "zh-Hans": "从本次充满到现在已经用掉的电；再次充电可以补回来，它不是老化。",
        "en": "Charge used since the last full state; charging restores it, so it is not battery aging.",
        "ja": "今回の満充電から使用した電力量です。再充電で戻るため、劣化ではありません。",
        "de": "Seit der letzten Vollladung verbrauchte Ladung; sie kommt beim Laden zurück und ist keine Alterung."
    },
    "hw.n.permanent_chemical": {
        "zh-Hans": "只有 Qmax 有效且落在合理边界时才拆出这部分；否则只显示设计容量与当前满充的总差额。",
        "en": "Shown separately only when Qmax is valid and bounded; otherwise only the total design-to-FCC gap is reported.",
        "ja": "Qmax が有効で妥当な範囲にある場合のみ分離し、それ以外は設計容量と FCC の総差だけを表示します。",
        "de": "Wird nur bei gültigem, plausibel begrenztem Qmax getrennt; sonst erscheint nur die Gesamtdifferenz zwischen Design und FCC."
    },
    "hw.range.weighted_ra": {
        "zh-Hans": "Apple 未公开阈值 · 只看本机趋势", "en": "No Apple threshold · use this Mac's trend",
        "ja": "Apple 公開しきい値なし · この Mac の傾向を見る", "de": "Kein Apple-Grenzwert · Trend dieses Mac beobachten"
    },
    "hw.range.compare_design": {
        "zh-Hans": "对比设计值 {value} mAh", "en": "Compare with {value} mAh design value",
        "ja": "設計値 {value} mAh と比較", "de": "Mit Designwert {value} mAh vergleichen"
    },
    "hw.range.current_capacity": {
        "zh-Hans": "0–{value} mAh", "en": "0–{value} mAh", "ja": "0–{value} mAh", "de": "0–{value} mAh"
    },
    "hw.range.nominal_relation": {
        "zh-Hans": "应≈ FCC + PackReserve", "en": "Should ≈ FCC + PackReserve",
        "ja": "FCC + PackReserve とほぼ一致", "de": "Sollte ≈ FCC + PackReserve sein"
    },
    "hw.range.time_valid": {
        "zh-Hans": "1–65,534 min · 65,535 = 不可用", "en": "1–65,534 min · 65,535 = unavailable",
        "ja": "1–65,534分 · 65,535 = 利用不可", "de": "1–65.534 min · 65.535 = nicht verfügbar"
    },
    "hw.range.cycle_rated": {
        "zh-Hans": "额定 {value} 次 · 超过不等于立即故障", "en": "Rated {value} cycles · exceeding it is not immediate failure",
        "ja": "定格 {value} 回 · 超えても直ちに故障ではない", "de": "Ausgelegt für {value} Zyklen · Überschreiten bedeutet keinen sofortigen Ausfall"
    },
    "hw.range.design_cycle_rated": {
        "zh-Hans": "额定 {value} 次", "en": "Rated {value} cycles", "ja": "定格 {value} 回", "de": "Ausgelegt für {value} Zyklen"
    },
    "hw.range.max_percent": {
        "zh-Hans": "0–100 % · Apple Silicon 原始口径", "en": "0–100 % · Apple silicon raw convention",
        "ja": "0–100 % · Apple Silicon の生値", "de": "0–100 % · Apple-Silicon-Rohwert"
    },
    "hw.range.max_platform": {
        "zh-Hans": "平台相关 · 可能为 mAh", "en": "Platform-specific · may be mAh",
        "ja": "プラットフォーム依存 · mAh の場合あり", "de": "Plattformabhängig · kann mAh sein"
    },
    "hw.range.temperature": {
        "zh-Hans": "15–35°C 常见舒适区", "en": "15–35°C common comfort band",
        "ja": "15–35°C の一般的な快適域", "de": "15–35°C üblicher Komfortbereich"
    },
    "hw.range.power_baseline": {
        "zh-Hans": "本机累计基线 ≈ {value} W", "en": "This Mac's cumulative baseline ≈ {value} W",
        "ja": "この Mac の累積基準 ≈ {value} W", "de": "Kumulative Basis dieses Mac ≈ {value} W"
    },
    "hw.range.lifetime_min": {
        "zh-Hans": "历史低点 · 低温会暂时缩短续航", "en": "Historical low · cold temporarily shortens runtime",
        "ja": "履歴最低 · 低温では一時的に駆動時間が短縮", "de": "Historischer Tiefstwert · Kälte verkürzt die Laufzeit vorübergehend"
    },
    "hw.range.lifetime_max": {
        "zh-Hans": "历史峰值 · ≥45°C 需关注热暴露", "en": "Historical peak · review heat exposure at ≥45°C",
        "ja": "履歴最高 · 45°C以上は熱暴露を確認", "de": "Historischer Höchstwert · ab 45°C Wärmebelastung prüfen"
    },
    "hw.range.lifetime_avg": {
        "zh-Hans": "15–35°C 常见使用区间", "en": "15–35°C common operating band",
        "ja": "15–35°C の一般的な使用域", "de": "15–35°C üblicher Betriebsbereich"
    },
    "hw.range.fault_zero": {
        "zh-Hans": "0 = 正常 · 非 0 需排查", "en": "0 = normal · investigate non-zero",
        "ja": "0 = 正常 · 0以外は要確認", "de": "0 = normal · Wert ungleich 0 prüfen"
    },
    "hw.range.qmax_valid": {
        "zh-Hans": "0 = 当前有效 · 非 0 需核验", "en": "0 = currently valid · verify non-zero",
        "ja": "0 = 現在有効 · 0以外は要確認", "de": "0 = aktuell gültig · Wert ungleich 0 prüfen"
    },
    "hw.range.port_zero": {
        "zh-Hans": "0 = 未记录失败 · 非 0 需排查", "en": "0 = no recorded failure · investigate non-zero",
        "ja": "0 = 失敗記録なし · 0以外は要確認", "de": "0 = kein Fehler protokolliert · Wert ungleich 0 prüfen"
    },
    "p.help_summary_soc": {
        "zh-Hans": "这里与系统菜单栏采用同一用户口径。原始 mAh 只用于容量拆解，不会覆盖 macOS 的 0–100%。",
        "en": "This uses the same user-facing charge level as the macOS menu bar. Raw mAh is used only for capacity breakdowns and never replaces macOS 0–100%.",
        "ja": "macOS メニューバーと同じユーザー向け残量を使います。生の mAh は容量内訳だけに使い、macOS の 0–100% を上書きしません。",
        "de": "Dies verwendet denselben nutzerseitigen Ladestand wie die macOS-Menüleiste. Rohwerte in mAh dienen nur der Kapazitätsaufteilung und ersetzen nie die macOS-Anzeige von 0–100 %."
    },
    "p.help_summary_health": {
        "zh-Hans": "主界面采用更接近系统设置的口径；容量条另给出不含安全预留的直接容量比例，两者分母不同。",
        "en": "The headline follows the system-aligned convention; the capacity bar separately shows the direct ratio without the safety reserve, so the denominators differ.",
        "ja": "主要表示はシステムに合わせた口径です。容量バーは安全予約を除く直接比率なので、分母が異なります。",
        "de": "Die Hauptanzeige folgt der systemnahen Konvention; der Kapazitätsbalken zeigt separat das direkte Verhältnis ohne Sicherheitsreserve, daher unterscheiden sich die Nenner."
    },
    "p.help_summary_power": {
        "zh-Hans": "优先读取 BatteryData.SystemPower；不可用时才依次退回 SystemLoad 或电压×电流。长期基线来自电量计累计遥测。",
        "en": "BatteryData.SystemPower is preferred; only when unavailable does the app fall back to SystemLoad or voltage × current. The long-term baseline comes from accumulated gauge telemetry.",
        "ja": "BatteryData.SystemPower を優先し、利用できない場合だけ SystemLoad、次に電圧×電流へフォールバックします。長期基準は電量計の累積テレメトリです。",
        "de": "BatteryData.SystemPower hat Vorrang; nur wenn es fehlt, wird auf SystemLoad oder Spannung × Strom zurückgegriffen. Die Langzeitbasis stammt aus der kumulierten Gauge-Telemetrie."
    },
    "p.help_summary_temperature": {
        "zh-Hans": "电量计字段在不同平台可能使用不同标度；服务层按原始量级解码，并保留原始值供核验。",
        "en": "Gauge temperature fields can use different scales across platforms; the service decodes by raw magnitude and preserves the raw value for verification.",
        "ja": "温度フィールドの尺度はプラットフォームで異なるため、生値の桁に応じて変換し、検証用に生値も保持します。",
        "de": "Temperaturfelder können je nach Plattform anders skaliert sein; der Dienst dekodiert nach Rohwertgröße und bewahrt den Rohwert zur Prüfung auf."
    },
    "p.help_summary_time_history": {
        "zh-Hans": "纵轴逐点记录 macOS 当时报告的剩余小时，横轴是采样时刻；相邻系统读数用阶梯连接，不按功率重算。",
        "en": "The vertical axis records the hours reported by macOS at each sample and the horizontal axis is sample time; readings are joined as steps and never recalculated from power.",
        "ja": "縦軸は各時点で macOS が報告した残り時間、横軸はサンプル時刻です。隣接値を階段状につなぎ、電力から再計算しません。",
        "de": "Die y-Achse zeigt die von macOS je Messpunkt gemeldeten Reststunden, die x-Achse die Messzeit; Werte werden als Stufen verbunden und nie aus der Leistung neu berechnet."
    },
    "p.help_summary_capacity": {
        "zh-Hans": "同一把尺下，先用 FCC 把容量分成可用与长期差额；Qmax 可信时，再把长期差额拆成暂时够不到和真正老化。",
        "en": "On one consistent scale, FCC first separates usable capacity from the long-term gap; only trustworthy Qmax data splits that gap into inaccessible charge and true aging.",
        "ja": "同じ尺度で、まず FCC により使用可能容量と長期差を分け、信頼できる Qmax がある場合だけ取り出せない分と真の劣化へ分解します。",
        "de": "Auf einer einheitlichen Skala trennt FCC zunächst nutzbare Kapazität und Langzeitdifferenz; nur vertrauenswürdiges Qmax teilt diese in unzugängliche Ladung und echte Alterung."
    },
    "p.help_summary_design_capacity": {
        "zh-Hans": "这台电池出厂时的标称容量，是容量拆解的总尺。",
        "en": "The battery's rated capacity when new is the reference scale for every capacity segment.",
        "ja": "新品時の定格容量で、すべての容量内訳の基準です。",
        "de": "Die Nennkapazität im Neuzustand ist der Maßstab für alle Kapazitätssegmente."
    },
    "p.help_summary_full_capacity": {
        "zh-Hans": "这块电池现在充满后，系统允许实际使用的总容量。",
        "en": "The total capacity the system currently allows this battery to deliver after a full charge.",
        "ja": "現在の満充電後にシステムが実際に使用可能とする総容量です。",
        "de": "Die Gesamtkapazität, die das System nach einer Vollladung derzeit tatsächlich freigibt."
    },
    "p.help_summary_used": {
        "zh-Hans": "这是从本次满充到现在流出的电，会在下一次充电时补回来；它和永久老化不能相加。",
        "en": "This charge has been used since the latest full state and returns on the next charge; it must not be added to permanent aging.",
        "ja": "今回の満充電から使った分で、次の充電で戻ります。永久劣化とは足し合わせません。",
        "de": "Diese Ladung wurde seit der letzten Vollladung verbraucht und kehrt beim nächsten Laden zurück; sie darf nicht zur dauerhaften Alterung addiert werden."
    },
    "p.help_summary_balance": {
        "zh-Hans": "串联电芯中最弱的一节会先触及截止线，因此压差越小，整包越同步。",
        "en": "The weakest cell in a series pack reaches cutoff first, so a smaller voltage spread means the pack stays better synchronized.",
        "ja": "直列パックでは最弱セルが先に終止電圧へ達するため、電圧差が小さいほど全体が揃っています。",
        "de": "In einem Reihenpack erreicht die schwächste Zelle zuerst die Abschaltgrenze; eine kleinere Spannungsdifferenz bedeutet bessere Synchronität."
    },
    "p.help_summary_resistance": {
        "zh-Hans": "显示最差一节的加权内阻，因为串联电池组会被阻力最高的一节限制；更重要的是观察同一台电脑的变化趋势。",
        "en": "The highest weighted cell resistance is shown because it limits a series pack; the trend on this same Mac matters more than a one-off value.",
        "ja": "直列パックは最大抵抗のセルに制限されるため最悪値を表示します。単発値より同じ Mac での推移が重要です。",
        "de": "Gezeigt wird der höchste gewichtete Zellwiderstand, weil er ein Reihenpack begrenzt; wichtiger als ein Einzelwert ist der Trend auf demselben Mac."
    },
    "p.help_summary_cycles": {
        "zh-Hans": "循环次数像里程表，只说明累计使用；是否需要检修仍需结合容量、内阻、电芯差和温度。",
        "en": "Cycle count is an odometer for accumulated use; service decisions still require capacity, resistance, cell spread and temperature together.",
        "ja": "サイクル数は累積使用の走行距離計です。整備判断には容量、抵抗、セル差、温度を合わせて見ます。",
        "de": "Die Zyklenzahl ist ein Kilometerzähler der Nutzung; für Serviceentscheidungen müssen Kapazität, Widerstand, Zellabweichung und Temperatur gemeinsam betrachtet werden."
    },
    "p.help_summary_voltage": {
        "zh-Hans": "电压会随电量和负载变化；单次高低不等于健康好坏，所以与这块电池自己的历史极限一起展示。",
        "en": "Voltage changes with charge and workload; one high or low reading is not battery health, so it is shown beside this battery's own lifetime extremes.",
        "ja": "電圧は残量と負荷で変化し、単発の高低だけで健康度は決まりません。そのためこの電池自身の履歴極値と併記します。",
        "de": "Die Spannung ändert sich mit Ladestand und Last; ein einzelner hoher oder niedriger Wert ist kein Gesundheitsurteil und wird daher mit den eigenen Extremwerten des Akkus gezeigt."
    },
    "p.help_origin_model": {
        "zh-Hans": "按 hw.model 匹配 Apple 机型公开规格", "en": "Apple model specification matched by hw.model",
        "ja": "hw.model で照合した Apple 公開モデル仕様", "de": "Über hw.model zugeordnete öffentliche Apple-Modellspezifikation"
    },
    "p.help_origin_derived": {
        "zh-Hans": "由上方列出的原始字段推导", "en": "Derived from the raw fields listed above",
        "ja": "上記の生フィールドから算出", "de": "Aus den oben aufgeführten Rohfeldern abgeleitet"
    },
    "p.help_origin_iokit": {
        "zh-Hans": "AppleSmartBattery IOKit 实时快照", "en": "AppleSmartBattery IOKit live snapshot",
        "ja": "AppleSmartBattery IOKit のライブスナップショット", "de": "Live-Snapshot von AppleSmartBattery IOKit"
    },
    "p.capacity_gap": {
        "zh-Hans": "长期容量总差额", "en": "Total long-term capacity gap",
        "ja": "長期容量の総差", "de": "Gesamte langfristige Kapazitätsdifferenz"
    },
    "p.capacity_gap_desc": {
        "zh-Hans": "目前满充容量比出厂设计少的总差额；Qmax 数据不足时不武断拆成够不到与真正老化。",
        "en": "The total gap between today's full charge and the original design; it is not split into inaccessible charge and true aging unless Qmax is valid.",
        "ja": "現在の満充電容量と設計値の総差です。Qmax が有効でない限り、取り出せない分と真の劣化へ無理に分解しません。",
        "de": "Die Gesamtdifferenz zwischen heutiger Vollladung und Designwert; ohne gültiges Qmax wird sie nicht in unzugängliche Ladung und echte Alterung zerlegt."
    },
    "p.capacity_gap_summary": {
        "zh-Hans": "这是设计容量与当前满充容量的总差；Qmax 可信时才继续拆分，不能把整个差额都叫化学老化。",
        "en": "This is the total design-to-FCC gap. It is split only when Qmax is trustworthy; the whole gap must not be called chemical aging.",
        "ja": "設計容量と現在の FCC の総差です。Qmax が信頼できる場合のみ分解し、全体を化学劣化とは呼びません。",
        "de": "Dies ist die Gesamtdifferenz zwischen Design und FCC. Sie wird nur bei vertrauenswürdigem Qmax zerlegt und nicht vollständig als chemische Alterung bezeichnet."
    },
    "p.derive_four": {
        "zh-Hans": "校验链：设计 {d} = 此刻还剩 {c} + 本次已用 {used} + 暂时够不到 {un} + 真正老化 {aged}；目前最大容量 {f} = {c} + {used}。",
        "en": "Check: design {d} = current {c} + used {used} + inaccessible {un} + true aging {aged}; current full capacity {f} = {c} + {used}.",
        "ja": "検算：設計 {d} = 現在 {c} + 使用済み {used} + 取り出せない {un} + 真の劣化 {aged}；現在の満充電容量 {f} = {c} + {used}。",
        "de": "Prüfung: Design {d} = aktuell {c} + verbraucht {used} + unzugänglich {un} + echte Alterung {aged}; heutige Vollladung {f} = {c} + {used}."
    },
    "p.derive_gap": {
        "zh-Hans": "校验链：设计 {d} = 此刻还剩 {c} + 本次已用 {used} + 长期容量总差额 {loss}；目前最大容量 {f} = {c} + {used}。Qmax 不足，暂不拆分总差额。",
        "en": "Check: design {d} = current {c} + used {used} + total long-term gap {loss}; current full capacity {f} = {c} + {used}. Qmax is insufficient, so the gap is not split.",
        "ja": "検算：設計 {d} = 現在 {c} + 使用済み {used} + 長期容量の総差 {loss}；現在の満充電容量 {f} = {c} + {used}。Qmax 不足のため総差は分解しません。",
        "de": "Prüfung: Design {d} = aktuell {c} + verbraucht {used} + gesamte Langzeitdifferenz {loss}; heutige Vollladung {f} = {c} + {used}. Qmax reicht zur Aufteilung nicht aus."
    },
}


def read_extra() -> dict[str, dict[str, str]]:
    module = ast.parse(PROTOTYPE.read_text(encoding="utf-8"))
    for node in module.body:
        if not isinstance(node, ast.Assign):
            continue
        if any(isinstance(target, ast.Name) and target.id == "EXTRA" for target in node.targets):
            value = ast.literal_eval(node.value)
            if not isinstance(value, dict):
                break
            return value
    raise RuntimeError("Could not find the literal EXTRA dictionary")


def escape_literal_percent(text: str) -> str:
    """Language packs reserve a single % for C format specifiers."""
    return text.replace("%", "%%")


def main() -> None:
    extra = read_extra() | APP_EXTRA
    changed = 0
    for path in sorted(LANGUAGE_DIR.glob("*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        code = payload["_meta"]["code"]
        strings = payload["strings"]
        before = dict(strings)

        for key, translations in extra.items():
            value = translations.get(code, translations["en"])
            strings[key] = escape_literal_percent(value)

        if strings != before:
            path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            changed += 1

    print(f"Merged {len(extra)} prototype strings into {changed} language packs")


if __name__ == "__main__":
    main()
