import Foundation
import Combine
import AppKit
import IOKit
import IOKit.ps

class BatteryService: ObservableObject {
    @Published var batteryData = BatteryData()
    @Published var chargingHistory: [ChargingSession] = []
    @Published var realtimeData: [RealtimeDataPoint] = []
    /// Four-layer live evidence merged with the 464-row metadata catalog.
    @Published private(set) var systemDataSnapshot = SystemDataSnapshot()
    @Published private(set) var isLiveRefreshEnabled = true
    /// 仅包含电池供电时由系统直接给出的有效剩余时间，约56秒一个持久化样本。
    @Published private(set) var runtimeSamples: [RuntimeSample] = []
    @Published var isLoadingHistory = false
    @Published var lastHistoryUpdate: Date? = nil
    /// 消费者层洞察。nil = 首帧还没算出来。
    @Published var insight: BatteryInsight? = nil

    private var timer: Timer?
    private var terminationObserver: NSObjectProtocol?
    /// Live power and process context refresh every ten seconds. Remaining-time
    /// history still applies RuntimeSample's 56-second de-duplication gate, so a
    /// faster UI poll never inflates the system-estimate sample count.
    static let liveRefreshInterval: TimeInterval = 10
    private let refreshInterval = BatteryService.liveRefreshInterval
    private var lastKnownPercent: Int? = nil
    private var lastKnownPercentTime: Date? = nil
    private let maxRealtimePoints = 180
    private let maxRuntimeSamples = 10_000
    /// Runtime history changes at the fuel-gauge cadence, but encoding and
    /// rewriting up to 10,000 samples every minute is needless disk activity.
    /// Keep live samples in memory and flush at most once every five minutes,
    /// plus on pause/termination.
    static let runtimePersistenceInterval: TimeInterval = 5 * 60
    private var runtimeHistoryDirty = false
    private var lastRuntimeHistorySave: Date?

    // Self-recording charging history
    private var currentSessionStart: Date? = nil
    private var currentSessionStartPercent: Int = 0
    private var wasCharging = false

    // History cache (sandboxed container)
    private let cacheDir: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let dir = base
            .appendingPathComponent("BatteryMonitor", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var historyCacheURL: URL { cacheDir.appendingPathComponent("history_cache.json") }
    private var socHistoryURL: URL { cacheDir.appendingPathComponent("soc_history.json") }
    private var runtimeHistoryURL: URL { cacheDir.appendingPathComponent("runtime_history.json") }

    /// 自记录的每日 SOC / 温度 / 满充存放快照。习惯评分、周报、循环速率都靠它。
    private var socHistory = SOCHistory()
    private var lastInsightRefresh: Date?
    /// 上次算 insight 时的语言，用来在切换语言后立即重算
    private var lastInsightLanguage: String?
    /// 洞察使用更慢的独立节流，避免同一批硬件值反复重算。
    private let insightRefreshInterval: TimeInterval = 30

    /// 最近一次进程采样，供耗电分析用
    private var latestProcesses: [ProcessPowerInfo] = []

    init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushPersistentState()
        }
    }

    deinit {
        timer?.invalidate()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func startMonitoring() {
        timer?.invalidate()
        loadCachedHistory()
        loadSOCHistory()
        loadRuntimeHistory()
        fetchData()
        guard isLiveRefreshEnabled else { return }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.fetchData()
        }
        // Give macOS room to coalesce this wake-up with process sampling and
        // other system maintenance without changing the visible 10-second rate.
        t.tolerance = min(1.5, refreshInterval * 0.15)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        flushPersistentState()
    }

    func setLiveRefreshEnabled(_ enabled: Bool) {
        guard enabled != isLiveRefreshEnabled else { return }
        isLiveRefreshEnabled = enabled
        if enabled {
            fetchData()
            scheduleTimer()
        } else {
            stopMonitoring()
        }
    }

    /// Manual refresh remains available while automatic refresh is paused.
    func refreshNow() { fetchData() }

    func refreshHistory() {
        // History is self-recorded; just reload from cache
        loadCachedHistory()
        lastHistoryUpdate = Date()
    }

    // MARK: - Native IOKit Data Fetching

    /// 电量计用65535表示尚未就绪/不适用；插电状态也不把它当剩余续航。
    static func preferredSystemTimeRemaining(
        isOnAC: Bool,
        timeRemaining: Int?,
        avgTimeToEmpty: Int?
    ) -> Int? {
        guard !isOnAC else { return nil }
        if let timeRemaining, RuntimeSample.isValid(minutes: timeRemaining) {
            return timeRemaining
        }
        if let avgTimeToEmpty, RuntimeSample.isValid(minutes: avgTimeToEmpty) {
            return avgTimeToEmpty
        }
        return nil
    }

    /// 功耗口径：BatteryData.SystemPower直读优先，SystemLoad次之，I×V只作回退。
    static func preferredPowerWatts(
        hardwareDetail: BatteryHardwareDetail,
        amperage: Int,
        voltage: Double
    ) -> Double {
        let direct = hardwareDetail.systemPowerWatts
        if direct.isFinite, direct > 0 { return direct }

        if hardwareDetail.systemLoad != 0 {
            return Double(abs(hardwareDetail.systemLoad)) / 1000.0
        }

        guard amperage != 0, voltage.isFinite, voltage > 0 else { return 0 }
        return Double(abs(amperage)) / 1000.0 * voltage
    }

    private func fetchData() {
        var data = BatteryData()
        data.lastUpdated = Date()
        data.batteryModel = Host.current().localizedName ?? ""
        data.modelIdentifier = Self.hardwareModel()

        // Get battery service from IOKit registry
        let batteryInfo = getBatteryProperties()

        if let info = batteryInfo {
            data.percent = info["CurrentCapacity"] as? Int ?? 0
            let maxCap = info["MaxCapacity"] as? Int ?? 100
            if maxCap > 0 && maxCap <= 100 {
                data.percent = Int(Double(data.percent) / Double(maxCap) * 100.0)
            }

            data.isCharging = (info["IsCharging"] as? Bool) ?? false
            data.isOnAC = (info["ExternalConnected"] as? Bool) ?? false
            data.isFullyCharged = (info["FullyCharged"] as? Bool) ?? false

            if let amperage = info["Amperage"] as? Int {
                data.amperage = amperage
            }
            if let voltage = info["Voltage"] as? Int {
                data.voltage = voltage > 1000 ? Double(voltage) / 1000.0 : Double(voltage)
            }
            if let cycleCount = info["CycleCount"] as? Int {
                data.cycleCount = cycleCount
            }
            if let temp = info["Temperature"] as? Int {
                data.temperatureCelsius = Self.decodeTemperature(temp)
            }
            if let designCap = info["DesignCapacity"] as? Int {
                data.designCapacity = designCap
            }
            if let rawMaxCap = info["AppleRawMaxCapacity"] as? Int, rawMaxCap > 200 {
                data.maxCapacity = rawMaxCap
            } else if let maxCapmAh = info["MaxCapacity"] as? Int, maxCapmAh > 200 {
                data.maxCapacity = maxCapmAh
            }

            // Charger wattage from AdapterDetails
            if let adapterDetails = info["AdapterDetails"] as? [String: Any] {
                if let watts = adapterDetails["Watts"] as? Int {
                    data.chargerWattage = watts
                } else if let watts = adapterDetails["AdapterWatts"] as? Int {
                    data.chargerWattage = watts
                }
            }

            data.hardwareDetail = Self.parseHardwareDetail(info, fallbackCycleCount: data.cycleCount)
            data.timeRemainingMinutes = Self.preferredSystemTimeRemaining(
                isOnAC: data.isOnAC,
                timeRemaining: data.hardwareDetail.timeRemainingRaw,
                avgTimeToEmpty: data.hardwareDetail.avgTimeToEmpty
            )

            // 主界面和洞察统一使用系统对齐口径；拿不到PackReserve才退回裸容量比例。
            if let systemHealth = data.hardwareDetail.systemHealthPercent,
               systemHealth.isFinite, systemHealth > 0 {
                data.maxCapacityPercent = min(100, max(0, Int(systemHealth.rounded())))
            } else if data.maxCapacity > 0 && data.designCapacity > 0 {
                let rawHealth = Double(data.maxCapacity) / Double(data.designCapacity) * 100.0
                data.maxCapacityPercent = min(100, max(0, Int(rawHealth.rounded())))
            }

            if data.maxCapacityPercent >= 80 {
                data.condition = .normal
            } else if data.maxCapacityPercent >= 60 {
                data.condition = .replaceSoon
            } else {
                data.condition = .replaceNow
            }
        }

        // Fallback: use IOPowerSources for basic info if IOKit failed
        if data.percent == 0 {
            fetchFromIOPowerSources(&data)
        }

        data.currentPowerWatts = Self.preferredPowerWatts(
            hardwareDetail: data.hardwareDetail,
            amperage: data.amperage,
            voltage: data.voltage
        )

        // Charge rate calculation
        calculateChargeRate(&data)

        // Self-record charging sessions
        recordChargingSession(data)

        // Add real-time data point
        let dataPoint = RealtimeDataPoint(
            timestamp: data.lastUpdated,
            voltage: data.voltage,
            amperage: Double(data.amperage),
            power: data.currentPowerWatts,
            temperature: data.temperatureCelsius,
            percent: data.percent,
            inputPower: data.hardwareDetail.systemPowerIn > 0
                ? Double(data.hardwareDetail.systemPowerIn) / 1000.0
                : nil,
            adapterVoltage: data.hardwareDetail.adapterVoltage > 0
                ? Double(data.hardwareDetail.adapterVoltage) / 1000.0
                : nil,
            adapterCurrent: data.hardwareDetail.adapterCurrent > 0
                ? Double(data.hardwareDetail.adapterCurrent) / 1000.0
                : nil
        )

        self.batteryData = data
        self.systemDataSnapshot = SystemDataCollector.collect(registry: batteryInfo)
        self.realtimeData.append(dataPoint)
        if self.realtimeData.count > self.maxRealtimePoints {
            self.realtimeData.removeFirst(self.realtimeData.count - self.maxRealtimePoints)
        }

        recordRuntimeSample(data)
        recordSOCSnapshot(data)
        refreshInsightIfNeeded(data)
    }

    // MARK: - Consumer Insight

    private func recordSOCSnapshot(_ data: BatteryData) {
        let before = socHistory
        socHistory.record(percent: data.percent,
                          cycleCount: data.cycleCount,
                          temperature: data.temperatureCelsius,
                          isCharging: data.isCharging,
                          isFullyCharged: data.isFullyCharged,
                          isOnAC: data.isOnAC)
        if socHistory != before { saveSOCHistory() }
    }

    /// 洞察是纯计算，但没必要在同一批硬件值上反复运行。
    /// 进程列表更新时，ProcessMonitorService 会单独触发一次。
    ///
    /// 语言变化也必须立即重算：InsightEngine 里的 headline / 各项 detail / note 是
    /// 在 body 之外算好存进结构体的本地化字符串，Observation 追踪不到它们。若不在
    /// 这里比对语言，切换语言后这些句子会残留旧语言直到下次 30 秒周期 —— 实测出现过
    /// 日语界面里夹一句中文诊断。
    /// （更彻底的做法是让 model 只存 key+参数、由 View 求值，但那要改 6 个字段和
    ///   所有构造点；这里比对语言能把不一致窗口压到 0，代价小得多。）
    private func refreshInsightIfNeeded(_ data: BatteryData, force: Bool = false) {
        let lang = L10n.shared.effectiveCode
        let languageChanged = lang != lastInsightLanguage
        if !force, !languageChanged, let last = lastInsightRefresh,
           Date().timeIntervalSince(last) < insightRefreshInterval { return }
        lastInsightRefresh = Date()
        lastInsightLanguage = lang
        insight = InsightEngine.analyze(data: data,
                                        history: chargingHistory,
                                        processes: latestProcesses,
                                        socLog: socHistory)
    }

    /// 由 ContentView 在进程列表更新时调用，让耗电分析跟得上进程变化。
    func updateProcesses(_ processes: [ProcessPowerInfo]) {
        latestProcesses = processes
        refreshInsightIfNeeded(batteryData, force: true)
    }

    private func loadSOCHistory() {
        guard let d = try? Data(contentsOf: socHistoryURL),
              let h = try? JSONDecoder().decode(SOCHistory.self, from: d) else { return }
        socHistory = h
    }

    private func saveSOCHistory() {
        guard let d = try? JSONEncoder().encode(socHistory) else { return }
        try? d.write(to: socHistoryURL, options: .atomic)
    }

    // MARK: - System Runtime History

    private func recordRuntimeSample(_ data: BatteryData) {
        guard !data.isOnAC, let minutes = data.timeRemainingMinutes else { return }
        let sample = RuntimeSample(timestamp: data.lastUpdated,
                                   minutesRemaining: minutes,
                                   percent: data.percent)
        guard RuntimeSample.shouldAppend(sample, after: runtimeSamples.last) else { return }

        runtimeSamples.append(sample)
        if runtimeSamples.count > maxRuntimeSamples {
            runtimeSamples.removeFirst(runtimeSamples.count - maxRuntimeSamples)
        }
        runtimeHistoryDirty = true
        saveRuntimeHistoryIfNeeded()
    }

    private func loadRuntimeHistory() {
        guard let data = try? Data(contentsOf: runtimeHistoryURL),
              let decoded = try? JSONDecoder().decode([RuntimeSample].self, from: data) else {
            runtimeSamples = []
            return
        }
        runtimeSamples = Array(decoded
            .filter { RuntimeSample.isValid(minutes: $0.minutesRemaining) }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(maxRuntimeSamples))
        runtimeHistoryDirty = false
        lastRuntimeHistorySave = (try? FileManager.default.attributesOfItem(atPath: runtimeHistoryURL.path)[.modificationDate]) as? Date
    }

    static func shouldPersistRuntimeHistory(
        dirty: Bool,
        lastSaved: Date?,
        now: Date,
        force: Bool = false
    ) -> Bool {
        guard dirty else { return false }
        guard !force else { return true }
        guard let lastSaved else { return true }
        return now.timeIntervalSince(lastSaved) >= runtimePersistenceInterval
    }

    private func saveRuntimeHistoryIfNeeded(force: Bool = false, now: Date = Date()) {
        guard Self.shouldPersistRuntimeHistory(
            dirty: runtimeHistoryDirty,
            lastSaved: lastRuntimeHistorySave,
            now: now,
            force: force
        ) else { return }
        guard let data = try? JSONEncoder().encode(runtimeSamples) else { return }
        do {
            try data.write(to: runtimeHistoryURL, options: .atomic)
            runtimeHistoryDirty = false
            lastRuntimeHistorySave = now
        } catch {
            // Preserve the dirty flag so the next scheduled or terminal flush
            // can retry instead of silently losing the pending samples.
        }
    }

    private func flushPersistentState() {
        saveRuntimeHistoryIfNeeded(force: true)
    }

    // MARK: - IOKit Battery Properties

    private func getBatteryProperties() -> [String: Any]? { Self.readRegistry() }

    /// 读 AppleSmartBattery 的全部属性。不依赖实例状态，抽成 static 便于测试与探针复用。
    static func readRegistry() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let props = properties?.takeRetainedValue() as NSDictionary? else {
            return nil
        }
        return props as? [String: Any]
    }

    // MARK: - IOPowerSources Fallback

    private func fetchFromIOPowerSources(_ data: inout BatteryData) {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(info, source).takeUnretainedValue() as? [String: Any] {
                if let level = desc[kIOPSCurrentCapacityKey] as? Int {
                    data.percent = level
                }
                if let isCharging = desc[kIOPSIsChargingKey] as? Bool {
                    data.isCharging = isCharging
                }
                if let isPresent = desc[kIOPSIsPresentKey] as? Bool, isPresent {
                    break
                }
            }
        }

        // Power source type (AC or Battery)
        if let psType = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
            data.isOnAC = (psType == kIOPSACPowerValue)
        }
    }

    // MARK: - Charge Rate

    private func calculateChargeRate(_ data: inout BatteryData) {
        let now = Date()
        guard data.isOnAC else {
            data.chargeRatePerHour = 0
            lastKnownPercent = data.percent
            lastKnownPercentTime = now
            return
        }
        if let lastPct = lastKnownPercent, let lastTime = lastKnownPercentTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed > 30 && data.percent != lastPct {
                let pctChange = data.percent - lastPct
                let hours = elapsed / 3600.0
                if hours > 0 && pctChange > 0 {
                    data.chargeRatePerHour = Double(pctChange) / hours
                }
            }
        }
        if data.percent != lastKnownPercent {
            lastKnownPercent = data.percent
            lastKnownPercentTime = now
        }
    }

    // MARK: - Self-Recording Charging History

    private func recordChargingSession(_ data: BatteryData) {
        let now = Date()

        if data.isCharging && !wasCharging {
            // Charging just started
            currentSessionStart = now
            currentSessionStartPercent = data.percent
        } else if !data.isCharging && wasCharging {
            // Charging just ended — record the session
            if let start = currentSessionStart {
                let duration = now.timeIntervalSince(start)
                let durationMinutes = Int(duration / 60.0)
                if durationMinutes >= 2 && data.percent > currentSessionStartPercent {
                    let pctChange = data.percent - currentSessionStartPercent
                    let ratePerHour = Double(pctChange) / (duration / 3600.0)

                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    let dateStr = formatter.string(from: start)
                    formatter.dateFormat = "HH:mm:ss"
                    let startStr = formatter.string(from: start)
                    let endStr = formatter.string(from: now)

                    let note = UsageLevel.from(ratePerHour: ratePerHour)

                    let session = ChargingSession(
                        date: dateStr,
                        startTime: startStr,
                        endTime: endStr,
                        startPercent: currentSessionStartPercent,
                        endPercent: data.percent,
                        durationMinutes: durationMinutes,
                        ratePerHour: ratePerHour,
                        note: note
                    )

                    chargingHistory.insert(session, at: 0)
                    // Keep last 50 sessions
                    if chargingHistory.count > 50 {
                        chargingHistory = Array(chargingHistory.prefix(50))
                    }
                    saveCachedHistory(chargingHistory)
                }
            }
            currentSessionStart = nil
        }

        wasCharging = data.isCharging
    }

    // MARK: - Cache

    private func loadCachedHistory() {
        guard let data = try? Data(contentsOf: historyCacheURL),
              let sessions = try? JSONDecoder().decode([ChargingSession].self, from: data) else { return }
        self.chargingHistory = sessions
        self.lastHistoryUpdate = try? FileManager.default.attributesOfItem(atPath: historyCacheURL.path)[.modificationDate] as? Date
    }

    private func saveCachedHistory(_ sessions: [ChargingSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: historyCacheURL, options: .atomic)
    }
}
