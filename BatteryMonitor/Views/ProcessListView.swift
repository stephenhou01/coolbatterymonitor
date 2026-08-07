import SwiftUI

struct ProcessListView: View {
    let processes: [ProcessPowerInfo]
    /// 是否已完成首次采样，用来区分「加载中」和「采过了但确实没有活跃进程」
    var hasSampled: Bool = true
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.batteryYellow)
                Text(L("proc.title"))
                    .font(AppTheme.Typography.sectionTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()

                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L("proc.refresh"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.chargingCyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.chargingCyan.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .pointerOnHover()

                HStack(spacing: 4) {
                    Circle().fill(AppTheme.batteryGreen).frame(width: 6, height: 6).opacity(0.8)
                    Text(L("proc.cpu_live"))
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.textTertiary)
                }
            }

            Text(L("proc.cpu_per_core_note"))
                .font(.system(size: 9.5))
                .foregroundStyle(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                ForEach(Array(processes.prefix(10).enumerated()), id: \.element.id) { index, proc in
                    ProcessRow(proc: proc, index: index)
                }
            }

            if processes.isEmpty {
                VStack(spacing: 8) {
                    if hasSampled {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 18))
                            .foregroundStyle(AppTheme.textTertiary)
                        Text(L("proc.empty"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)
                    } else {
                        ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                        Text(L("proc.loading"))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
    }

}

struct ProcessRow: View {
    let proc: ProcessPowerInfo
    let index: Int
    @State private var appeared = false
    @State private var isHovering = false
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isExpanded.toggle() }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.energyColor(proc.energyImpact).opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: iconName(for: proc.displayName))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.energyColor(proc.energyImpact))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(proc.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)
                        Text(ProcessRow.subtitle(for: proc))
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.textTertiary)
                            .lineLimit(1)
                            .help(L("proc.memory_rss_note"))
                    }
                    .frame(width: 140, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(AppTheme.contrastOverlay(0.04))
                                .frame(height: 18)

                            let fraction = ProcessRow.barFraction(cpuPercent: proc.cpuPercent)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [AppTheme.energyColor(proc.energyImpact).opacity(0.4), AppTheme.energyColor(proc.energyImpact)],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: appeared ? CGFloat(fraction) * geo.size.width : 0, height: 18)
                                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: appeared)
                                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: fraction)
                        }
                    }
                    .frame(height: 18)

                    HStack(spacing: 4) {
                        Text(ProcessRow.cpuText(proc.cpuPercent))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.energyColor(proc.energyImpact))
                            .contentTransition(.numericText(value: proc.cpuPercent))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppTheme.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    // 72 而不是 62：修好 timebase 后会出现 "412.3%" 这种三位数读数，
                    // 62pt 只够装 "9.9%"，会把 chevron 挤掉。
                    .frame(width: 72, alignment: .trailing)
                }

                if isExpanded {
                    CPUSparkline(history: proc.cpuHistory, color: AppTheme.energyColor(proc.energyImpact))
                        .padding(.top, 8)
                        .padding(.horizontal, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(proc.displayName)
        .accessibilityValue(LNum("%.1f%% CPU", proc.cpuPercent))
        .accessibilityHint(L("proc.cpu_trend"))
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.contrastOverlay(isHovering ? 0.06 : (appeared ? 0.02 : 0))))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.05)) { appeared = true }
        }
    }

    private func iconName(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("chrome") || lower.contains("safari") || lower.contains("firefox") { return "globe" }
        if lower.contains("dingtalk") || lower.contains("lark") || lower.contains("feishu") { return "message.fill" }
        if lower.contains("qoder") || lower.contains("codex") || lower.contains("code") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("excel") || lower.contains("sheets") || lower.contains("numbers") { return "tablecells.fill" }
        if lower.contains("alibaba") || lower.contains("dingtalksecurity") || lower.contains("antivirus") { return "shield.fill" }
        if lower.contains("terminal") || lower.contains("shell") || lower.contains("zsh") { return "terminal.fill" }
        if lower.contains("window") || lower.contains("system") { return "gearshape.fill" }
        if lower.contains("qianwen") || lower.contains("chat") { return "bubble.left.and.bubble.right.fill" }
        return "app.fill"
    }

    /// 进度条用**绝对刻度**：满格 = 占满一个核（100%）。
    /// 以前按「本次列表里的最大值」归一化，空闲机器上最重的进程哪怕只有 1.7% 也会画满格，
    /// 让人误以为它吃掉了大部分电。绝对刻度下空闲就是短条，这是对的。
    /// 多核聚合行可能超 100% 并同时满格，靠右侧数字和 energyColor 区分。
    static func barFraction(cpuPercent: Double) -> Double {
        guard cpuPercent.isFinite, cpuPercent > 0 else { return 0 }
        return min(1, cpuPercent / 100)
    }

    /// ≥100% 时去掉小数：进程 CPU 的 0.1% 精度没有意义，而四位数字会把固定宽度撑爆。
    static func cpuText(_ cpuPercent: Double) -> String {
        cpuPercent >= 100 ? LNum("%.0f%%", cpuPercent) : LNum("%.1f%%", cpuPercent)
    }

    /// 副标题。以前显示的是 `PID n`，但一行现在是 app + 子进程的聚合，代表 pid 对用户
    /// 没有意义；有价值的信息是「合并了几个进程」和「其中最重的是哪个」。
    /// 单进程行退回只显示内存，不硬凑一个「1 个进程」的废话。
    static func subtitle(for proc: ProcessPowerInfo) -> String {
        let memory = LNum("%.0fMB", proc.memoryMB)
        guard proc.processCount > 1 else { return memory }
        // 只在 processCount > 1 时渲染，顺带绕开 de/fr/it/pt/es 的单复数问题 ——
        // 不需要 stringsdict。
        let group = proc.topChildName.map { L("proc.group_subtitle", $0, proc.processCount) }
            ?? L("proc.group_count", proc.processCount)
        return "\(group) · \(memory)"
    }
}

// MARK: - CPU Sparkline

struct CPUSparkline: View {
    let history: [Double]
    let color: Color

    private var peak: Double { max(history.max() ?? 1, 1) }
    private var avg: Double { history.isEmpty ? 0 : history.reduce(0, +) / Double(history.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Text(L("proc.cpu_trend"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(AppTheme.textTertiary.opacity(0.5))
                        .help(L("tip.cpu"))
                }
                Spacer()
                statLabel(L("proc.peak"), LNum("%.1f%%", peak))
                statLabel(L("proc.avg"), LNum("%.1f%%", avg))
                // ProcessMonitorService 与电池服务都按 10 秒刷新；旧 key 仍写着 5 秒，
                // 这里直接复用已完整翻译的真实周期文案，避免误导用户。
                Text("\(L("p.live_10s")) · \(history.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textTertiary)
            }

            if history.count < 2 {
                Text(L("proc.collecting"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            } else {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let stepX = history.count > 1 ? w / CGFloat(history.count - 1) : w
                    let points = history.enumerated().map { i, v in
                        CGPoint(x: CGFloat(i) * stepX,
                                y: h - CGFloat(v / peak) * h)
                    }

                    ZStack {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: h))
                            for pt in points { p.addLine(to: pt) }
                            p.addLine(to: CGPoint(x: points.last!.x, y: h))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom))
                        Path { p in
                            p.move(to: points[0])
                            for pt in points.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .position(points.last!)
                    }
                }
                .frame(height: 44)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.contrastOverlay(0.03)))
    }

    private func statLabel(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}
