import SwiftUI

// MARK: - 健康诊断书

struct HealthDiagnosisCard: View {
    let diagnosis: HealthDiagnosis
    @State private var showFactors = false

    private var levelColor: Color { AppTheme.healthColor(diagnosis.level) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(key: "insight.section.health")

            HStack(alignment: .top, spacing: 20) {
                scoreRing
                VStack(alignment: .leading, spacing: 5) {
                    Text(L(diagnosis.level.labelKey))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(levelColor)
                        .tracking(0.5)
                    Text(diagnosis.headline)
                        .font(.system(size: 12.5))
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                metaColumn
            }

            if showFactors {
                VStack(spacing: 7) {
                    ForEach(diagnosis.factors) { FactorRow(factor: $0) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { showFactors.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(showFactors ? L("insight.collapse") : L("insight.expand_factors"))
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(showFactors ? 180 : 0))
                }
                .foregroundStyle(AppTheme.chargingCyan)
            }
            .buttonStyle(.plain)
            .pointerOnHover()
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
        .modifier(AppTheme.Scanline())
        .modifier(AppTheme.hoverLift(accent: levelColor))
    }

    private var scoreRing: some View {
        ZStack {
            Circle().stroke(levelColor.opacity(0.15), lineWidth: 7)
            RingProgress(fraction: Double(diagnosis.score) / 100, color: levelColor, lineWidth: 7)
            CountUp(value: diagnosis.score,
                    font: .system(size: 25, weight: .bold, design: .rounded),
                    color: levelColor)
        }
        .frame(width: 74, height: 74)
    }

    /// 右侧四项摘要。剩余寿命刻意不给日历日期 —— 见 InsightEngine 顶部说明。
    private var metaColumn: some View {
        VStack(alignment: .trailing, spacing: 7) {
            let life = diagnosis.remainingLife
            if let m = life.estimatedMonths {
                metaItem(L("insight.life.label"), L("insight.life.months", m / 12, m % 12))
            } else if let c = life.remainingCycles {
                metaItem(L("insight.life.label"), L("insight.life.remaining_cycles", c),
                         hint: L("insight.life.observing", life.observedDays, life.daysNeeded))
            }
            if let age = diagnosis.age {
                metaItem(L("insight.age.label"),
                         L("insight.age.value", age.years, age.months) + " " + estimatedTag,
                         help: L("insight.age.tip"))
            }
            if let cycles = diagnosis.factors.first(where: { $0.labelKey == "insight.factor.cycles" }) {
                metaItem(L("insight.factor.cycles"), cycles.rawValue)
            }
            if let cap = diagnosis.factors.first(where: { $0.labelKey == "insight.factor.capacity" }) {
                metaItem(L("insight.factor.capacity"), cap.consumerDetail)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var estimatedTag: String { "(\(L("insight.estimated")))" }

    private func metaItem(_ label: String, _ value: String,
                          hint: String? = nil, help: String? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            if let hint {
                Text(hint)
                    .font(.system(size: 8.5))
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.8))
            }
        }
        .help(help ?? "")
    }
}

/// 评分环，入场时从 0 扫到目标比例。
struct RingProgress: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: max(0.001, min(1, shown)))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .shadow(color: color.opacity(0.5), radius: 5)
            .onAppear {
                guard !reduceMotion else { shown = fraction; return }
                withAnimation(.easeOut(duration: 1.0)) { shown = fraction }
            }
            .onChange(of: fraction) { _, f in
                withAnimation(.easeOut(duration: 0.5)) { shown = f }
            }
    }
}

struct FactorRow: View {
    let factor: HealthFactor
    private var color: Color { AppTheme.statusColor(factor.status) }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: factor.status == .pass ? "checkmark" :
                    (factor.status == .warn ? "exclamationmark" : "xmark"))
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(color)
                .frame(width: 16, height: 16)
                .background(Circle().fill(color.opacity(0.15)))
            Image(systemName: factor.icon)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textTertiary)
                .frame(width: 14)
            Text(L(factor.labelKey))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
            Text(factor.consumerDetail)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(factor.rawValue)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(AppTheme.textTertiary.opacity(0.75))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(0.025)))
    }
}

// MARK: - 充电习惯

struct ChargingHabitCard: View {
    let habit: ChargingHabitScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(key: "insight.section.habit")

            if let score = habit.score {
                HStack(alignment: .center, spacing: 12) {
                    Text(habit.grade)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.chargingCyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(score) / 100")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.textPrimary)
                        ProgressBar(fraction: Double(score) / 100, color: AppTheme.chargingCyan)
                            .frame(height: 4)
                    }
                    Spacer()
                }
                VStack(spacing: 5) {
                    ForEach(habit.behaviors) { BehaviorRow(item: $0) }
                }
                if let tip = habit.topSuggestion { SuggestionBox(text: tip) }
            } else {
                CollectingPlaceholder(days: habit.daysCollected, needed: habit.daysNeeded)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(AppTheme.card())
        .modifier(AppTheme.hoverLift())
    }
}

struct BehaviorRow: View {
    let item: BehaviorItem
    private var color: Color { AppTheme.statusColor(item.status) }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.status == .pass ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(L(item.labelKey))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
            Text(item.detail)
                .font(.system(size: 10.5))
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 配件诊断

struct AccessoryCard: View {
    let accessory: AccessoryDiagnosis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(key: "insight.section.accessory")

            HStack(spacing: 9) {
                Image(systemName: accessory.isConnected ? "powerplug.fill" : "powerplug")
                    .font(.system(size: 15))
                    .foregroundStyle(accessory.isConnected ? AppTheme.batteryGreen : AppTheme.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(accessory.summary)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                    if !accessory.subtitle.isEmpty {
                        Text(accessory.subtitle)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            if accessory.isConnected {
                VStack(spacing: 5) {
                    ForEach(accessory.checks) { check in
                        HStack(spacing: 7) {
                            Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(check.passed ? AppTheme.batteryGreen : AppTheme.batteryRed)
                            Text(L(check.labelKey))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text(check.detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                if let tip = accessory.suggestion { SuggestionBox(text: tip) }
            } else {
                Text(accessory.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(AppTheme.card())
        .modifier(AppTheme.hoverLift(accent: AppTheme.accentPurple))
    }
}

// MARK: - 耗电分析

struct PowerAnalysisCard: View {
    let analysis: PowerAnalysis
    private var color: Color { AppTheme.powerLevelColor(analysis.level) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionLabel(key: "insight.section.power")

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LNum("%.1f", analysis.currentWatts))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: analysis.currentWatts))
                Text("W").font(.system(size: 13, weight: .semibold)).foregroundStyle(color.opacity(0.8))
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 5, height: 5)
                    Text(L(analysis.level.labelKey))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(color)
                }
                .padding(.leading, 4)
                Spacer()
                Text(analysis.estimatedHoursRemaining.map { L("insight.power.eta", $0) }
                        ?? L("insight.power.on_ac"))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            let maxCPU = max(analysis.topConsumers.first?.cpuPercent ?? 1, 1)
            VStack(spacing: 5) {
                ForEach(Array(analysis.topConsumers.enumerated()), id: \.element.id) { i, proc in
                    HStack(spacing: 8) {
                        Text(String(format: "%02d", i + 1))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.textTertiary.opacity(0.7))
                        Text(proc.displayName)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                            .frame(width: 128, alignment: .leading)
                        ProgressBar(fraction: proc.cpuPercent / maxCPU,
                                    color: AppTheme.energyColor(proc.energyImpact))
                            .frame(height: 5)
                        Text(LNum("%.1f%%", proc.cpuPercent))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.energyColor(proc.energyImpact))
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            if let note = analysis.note { SuggestionBox(text: note) }
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
        .modifier(AppTheme.hoverLift(accent: color))
    }
}

// MARK: - 周报

struct WeeklyReportCard: View {
    let report: WeeklyHabitReport

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionLabel(key: "insight.section.weekly")

            if report.isReady {
                HStack(spacing: 10) {
                    statTile("\(report.chargeCount)", L("insight.weekly.charges"), AppTheme.chargingCyan)
                    statTile("\(report.avgMaxSoc)%", L("insight.weekly.avg_max"), AppTheme.batteryGreen)
                    statTile("\(report.avgMinSoc)%", L("insight.weekly.avg_min"), AppTheme.batteryYellow)
                    statTile(LNum("%.0f°C", report.maxTemp), L("insight.weekly.max_temp"), AppTheme.batteryOrange)
                }
                HStack(spacing: 8) {
                    Text(L("insight.weekly.grade"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(report.grade)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.batteryGreen)
                    Spacer()
                }
            } else {
                CollectingPlaceholder(days: report.daysCollected, needed: report.daysNeeded)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
        .modifier(AppTheme.hoverLift())
    }

    private func statTile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.08)))
    }
}

// MARK: - 共用小件

struct ProgressBar: View {
    let fraction: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.55), color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, min(1, shown) * geo.size.width))
            }
        }
        .onAppear {
            guard !reduceMotion else { shown = fraction; return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { shown = fraction }
        }
        .onChange(of: fraction) { _, f in
            withAnimation(.easeOut(duration: 0.35)) { shown = f }
        }
    }
}

/// 建议框。只放能执行的建议，或者陈述事实 —— 不放编造的量化收益。
struct SuggestionBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.batteryYellow)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppTheme.batteryYellow.opacity(0.07)))
    }
}

/// 数据不足时的占位。诚实告知还要几天，而不是显示编造的数字。
struct CollectingPlaceholder: View {
    let days: Int
    let needed: Int

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "hourglass")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.textTertiary)
            Text(L("insight.collecting"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            Text(L("insight.days_left", max(0, needed - days)))
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
    }
}
