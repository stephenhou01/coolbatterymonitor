import SwiftUI

struct ProcessListView: View {
    let processes: [ProcessPowerInfo]
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

            VStack(spacing: 6) {
                ForEach(Array(processes.prefix(10).enumerated()), id: \.element.id) { index, proc in
                    ProcessRow(proc: proc, index: index, maxCpu: maxCpu)
                }
            }

            if processes.isEmpty {
                VStack(spacing: 8) {
                    ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                    Text(L("proc.loading"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
    }

    private var maxCpu: Double { max(processes.map(\.cpuPercent).max() ?? 100, 1) }
}

struct ProcessRow: View {
    let proc: ProcessPowerInfo
    let index: Int
    let maxCpu: Double
    @State private var appeared = false
    @State private var isHovering = false
    @State private var isExpanded = false

    var body: some View {
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
                Text("PID \(proc.pid) · \(String(format: "%.0fMB", proc.memoryMB))")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(width: 140, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 18)

                    let fraction = min(max(proc.cpuPercent / maxCpu, 0), 1.0)
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
                Text(String(format: "%.1f%%", proc.cpuPercent))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.energyColor(proc.energyImpact))
                    .contentTransition(.numericText(value: proc.cpuPercent))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .frame(width: 62, alignment: .trailing)
        }

        if isExpanded {
            CPUSparkline(history: proc.cpuHistory, color: AppTheme.energyColor(proc.energyImpact))
                .padding(.top, 8)
                .padding(.horizontal, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isExpanded.toggle() }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(isHovering ? 0.06 : (appeared ? 0.02 : 0))))
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
                statLabel(L("proc.peak"), String(format: "%.1f%%", peak))
                statLabel(L("proc.avg"), String(format: "%.1f%%", avg))
                Text(L("proc.interval", history.count))
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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.03)))
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
