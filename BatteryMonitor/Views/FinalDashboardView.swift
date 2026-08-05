import SwiftUI
import Charts

/// Native SwiftUI migration of `Prototype/battery-final.html`.
///
/// The view is intentionally an information hierarchy, not a collection of the
/// legacy dashboard widgets: runtime first, then the three supporting signals,
/// followed by explanation and raw evidence.
struct FinalDashboardView: View {
    @EnvironmentObject private var batteryService: BatteryService
    @EnvironmentObject private var processService: ProcessMonitorService
    let batteryData: BatteryData
    let realtimeData: [RealtimeDataPoint]
    var persistedRuntimeSamples: [RuntimeSample] = []
    @Binding var selectedHelp: MetricHelpContent?

    @State private var sessionRuntimeSamples: [RuntimeSample] = []

    private var snapshot: DashboardMetricSnapshot {
        DashboardMetricSnapshot(data: batteryData, realtimeData: realtimeData)
    }

    private var chartSamples: [RuntimeSample] {
        persistedRuntimeSamples.isEmpty ? sessionRuntimeSamples : persistedRuntimeSamples
    }

    var body: some View {
        // The nine sections below are built as they come into view rather than
        // all at once; only the first screenful is on the path to first paint.
        LazyVStack(spacing: 16) {
            RemainingTimeHeroSection(snapshot: snapshot, selectedHelp: $selectedHelp)

            if let specification = snapshot.specification {
                RuntimeBenchmarkSection(
                    snapshot: snapshot,
                    specification: specification,
                    selectedHelp: $selectedHelp
                )
            }

            PowerCenterSection(
                snapshot: snapshot,
                points: realtimeData,
                processes: processService.topProcesses,
                hasProcessSample: processService.hasSampled,
                systemCPU: processService.systemCPU,
                isLive: batteryService.isLiveRefreshEnabled,
                onToggleLive: toggleLiveRefresh,
                onRefresh: refreshNow,
                selectedHelp: $selectedHelp
            )

            RemainingTimeHistorySection(
                snapshot: snapshot,
                samples: chartSamples,
                selectedHelp: $selectedHelp
            )

            CapacityBreakdownSection(snapshot: snapshot, selectedHelp: $selectedHelp)
            MetricReferenceSection(snapshot: snapshot, selectedHelp: $selectedHelp)
            ConsumerExplanationSection(snapshot: snapshot)
            CompleteHardwareDetailView(data: batteryData, selectedHelp: $selectedHelp)
            SystemDataWorkbenchView(
                snapshot: batteryService.systemDataSnapshot,
                gaugeReadAt: batteryData.hardwareDetail.gaugeUpdateTime,
                isLive: batteryService.isLiveRefreshEnabled,
                onToggleLive: toggleLiveRefresh,
                onRefresh: refreshNow,
                selectedHelp: $selectedHelp
            )
        }
        .onAppear(perform: recordRuntimeSampleIfNeeded)
        .onChange(of: batteryData.lastUpdated) { _, _ in recordRuntimeSampleIfNeeded() }
    }

    private func toggleLiveRefresh() {
        let enabled = !batteryService.isLiveRefreshEnabled
        batteryService.setLiveRefreshEnabled(enabled)
        processService.setLiveRefreshEnabled(enabled)
    }

    private func refreshNow() {
        batteryService.refreshNow()
        processService.fetchProcesses()
    }

    /// UI-only session fallback. BatteryService can pass persisted samples once
    /// available; either way, invalid sentinels and sub-56-second duplicates are
    /// rejected by the shared RuntimeSample rules.
    private func recordRuntimeSampleIfNeeded() {
        guard persistedRuntimeSamples.isEmpty,
              !batteryData.isOnAC,
              let minutes = batteryData.timeRemainingMinutes else { return }
        let candidate = RuntimeSample(
            timestamp: batteryData.lastUpdated,
            minutesRemaining: minutes,
            percent: batteryData.percent
        )
        guard RuntimeSample.shouldAppend(candidate, after: sessionRuntimeSamples.last) else { return }
        sessionRuntimeSamples.append(candidate)
        if sessionRuntimeSamples.count > 240 {
            sessionRuntimeSamples.removeFirst(sessionRuntimeSamples.count - 240)
        }
    }
}

// MARK: - Shared dashboard chrome

struct DashboardSectionHeader: View {
    let icon: String
    let title: String
    let color: Color
    /// Lazy so the sheet is built on tap, not on every redraw of the card.
    let help: (() -> MetricHelpContent)?
    @Binding var selection: MetricHelpContent?
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 9) {
            MetricGlyph(systemName: icon, tint: color, scale: .compact)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
            if let help { MetricHelpButton(content: help(), selection: $selection) }
            Spacer()
            if let trailing { trailing }
        }
    }
}

private struct FinalDashboardCardModifier: ViewModifier {
    let accent: Color
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [AppTheme.surfaceRaised, AppTheme.cardBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(hovering ? accent.opacity(0.26) : AppTheme.contrastOverlay(0.065), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.30), radius: hovering ? 26 : 18, y: 8)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.18), value: hovering)
    }
}

extension View {
    func finalDashboardCard(accent: Color) -> some View {
        modifier(FinalDashboardCardModifier(accent: accent))
    }
}
