import SwiftUI

struct HistoryChartView: View {
    let sessions: [ChargingSession]
    let isLoading: Bool
    let onRefresh: () -> Void
    @State private var animatedBars = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accentPurple)
                Text(L("hist.title"))
                    .font(AppTheme.Typography.sectionTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()

                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L("hist.refresh"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.chargingCyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppTheme.chargingCyan.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .pointerOnHover()
                .disabled(isLoading)

                if isLoading { ProgressView().controlSize(.mini) }
            }

            if isLoading && sessions.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                    Text(L("hist.analyzing"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if sessions.isEmpty && !isLoading {
                emptyState
            } else if !sessions.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(Array(sessions.prefix(8).enumerated()), id: \.element.id) { index, session in
                            SessionRow(session: session, delay: Double(index) * 0.08)
                        }
                    }
                }
                .frame(maxHeight: 280)

                rateChart
            }
        }
        .padding(AppTheme.Spacing.xl)
        .modifier(AppTheme.card())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "battery.25")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.textTertiary)
            Text(L("hist.empty"))
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
            Text(L("hist.empty_hint"))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var rateChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(L("hist.rate_chart"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary.opacity(0.5))
                    .help(L("tip.charge_rate"))
            }

            let maxRate = max(sessions.map(\.ratePerHour).max() ?? 60, 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: AppTheme.Spacing.sm) {
                    ForEach(Array(sessions.prefix(8).enumerated()), id: \.element.id) { index, session in
                        VStack(spacing: 4) {
                            Text(LNum("%.0f%%", max(session.ratePerHour, 0)))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.rateColor(session.ratePerHour))

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [AppTheme.rateColor(session.ratePerHour).opacity(0.5), AppTheme.rateColor(session.ratePerHour)],
                                    startPoint: .bottom, endPoint: .top
                                ))
                                .frame(width: 28, height: animatedBars ? max(CGFloat(session.ratePerHour / maxRate * 80), 2) : 2)
                                .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(Double(index) * 0.1), value: animatedBars)

                            Text(formatShortDate(session.date))
                                .font(.system(size: 8))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 110)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { animatedBars = true }
        }
    }

    private func formatShortDate(_ date: String) -> String {
        let parts = date.components(separatedBy: "-")
        guard parts.count == 3 else { return date }
        return "\(parts[1])/\(parts[2])"
    }
}

struct SessionRow: View {
    let session: ChargingSession
    let delay: Double
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.date)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(session.startTime) - \(session.endTime)")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .frame(width: 100, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.contrastOverlay(0.06))
                        .frame(height: 24)

                    let startFrac = CGFloat(min(max(session.startPercent, 0), 100)) / 100.0
                    let endFrac = CGFloat(min(max(session.endPercent, 0), 100)) / 100.0
                    let width = appeared ? max(endFrac - startFrac, 0) * geo.size.width : 0

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(
                            colors: [AppTheme.rateColor(session.ratePerHour).opacity(0.6), AppTheme.rateColor(session.ratePerHour)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(width, 4), height: 24)
                        .offset(x: appeared ? startFrac * geo.size.width : 0)
                        .animation(.spring(response: 0.9, dampingFraction: 0.65).delay(delay), value: appeared)

                    HStack {
                        Text("\(session.startPercent)%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.leading, 6)
                        Spacer()
                        Text("\(session.endPercent)%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.trailing, 6)
                    }
                }
            }
            .frame(height: 24)

            VStack(alignment: .trailing, spacing: 2) {
                Text(LNum("%.0f%@", session.ratePerHour, L("hist.rate_unit")))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.rateColor(session.ratePerHour))
                Text(L("hist.duration", session.durationMinutes, session.note.localizedDescription))
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -20)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
            }
        }
    }
}
