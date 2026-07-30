import Foundation
import Combine
import IOKit
import IOKit.ps

class BatteryService: ObservableObject {
    @Published var batteryData = BatteryData()
    @Published var chargingHistory: [ChargingSession] = []
    @Published var realtimeData: [RealtimeDataPoint] = []
    @Published var isLoadingHistory = false
    @Published var lastHistoryUpdate: Date? = nil
    /// 消费者层洞察。nil = 首帧还没算出来。
    @Published var insight: BatteryInsight? = nil

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 3
    private var lastKnownPercent: Int? = nil
    private var lastKnownPercentTime: Date? = nil
    private let maxRealtimePoints = 60

    // Self-recording charging history
    private var currentSessionStart: Date? = nil
    private var currentSessionStartPercent: Int = 0
    private var wasCharging = false

    // History cache (sandboxed container)
    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BatteryMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var historyCacheURL: URL { cacheDir.appendingPathComponent("history_cache.json") }
    private var socHistoryURL: URL { cacheDir.appendingPathComponent("soc_history.json") }

    /// 自记录的每日 SOC / 温度 / 满充存放快照。习惯评分、周报、循环速率都靠它。
    private var socHistory = SOCHistory()
    private var lastInsightRefresh: Date?
    /// 硬件参数变化慢，洞察不需要每 3 秒重算
    private let insightRefreshInterval: TimeInterval = 30

    /// 最近一次进程采样，供耗电分析用
    private var latestProcesses: [ProcessPowerInfo] = []

    func startMonitoring() {
        loadCachedHistory()
        loadSOCHistory()
        fetchData()
        let t = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.fetchData()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refreshHistory() {
        // History is self-recorded; just reload from cache
        loadCachedHistory()
        lastHistoryUpdate = Date()
    }

    // MARK: - Native IOKit Data Fetching

    private func fetchData() {
        var data = BatteryData()
        data.lastUpdated = Date()
        data.batteryModel = Host.current().localizedName ?? ""

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

            // Time remaining
            // -1 表示系统仍在测算；保持 nil 交给 View 显示「计算中」
            if let timeRemaining = info["TimeRemaining"] as? Int, timeRemaining > 0 {
                data.timeRemainingMinutes = timeRemaining
            }

            // Charger wattage from AdapterDetails
            if let adapterDetails = info["AdapterDetails"] as? [String: Any] {
                if let watts = adapterDetails["Watts"] as? Int {
                    data.chargerWattage = watts
                } else if let watts = adapterDetails["AdapterWatts"] as? Int {
                    data.chargerWattage = watts
                }
            }

            // Battery health
            if data.maxCapacity > 0 && data.designCapacity > 0 {
                let health = Int(Double(data.maxCapacity) / Double(data.designCapacity) * 100.0)
                if health > 0 && health <= 100 {
                    data.maxCapacityPercent = health
                }
            }

            // Condition based on health
            if data.maxCapacityPercent >= 80 {
                data.condition = .normal
            } else if data.maxCapacityPercent >= 60 {
                data.condition = .replaceSoon
            } else {
                data.condition = .replaceNow
            }

            data.hardwareDetail = Self.parseHardwareDetail(info, fallbackCycleCount: data.cycleCount)
        }

        // Fallback: use IOPowerSources for basic info if IOKit failed
        if data.percent == 0 {
            fetchFromIOPowerSources(&data)
        }

        // Power calculation: P = |I| × V
        if data.amperage != 0 && data.voltage > 0 {
            data.currentPowerWatts = Double(abs(data.amperage)) / 1000.0 * data.voltage
        }

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
            percent: data.percent
        )

        self.batteryData = data
        self.realtimeData.append(dataPoint)
        if self.realtimeData.count > self.maxRealtimePoints {
            self.realtimeData.removeFirst(self.realtimeData.count - self.maxRealtimePoints)
        }

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

    /// 洞察是纯计算，但没必要每 3 秒跑一遍 —— 硬件参数变化慢。
    /// 进程列表变化快，所以 ProcessMonitorService 刷新时会单独触发一次。
    private func refreshInsightIfNeeded(_ data: BatteryData, force: Bool = false) {
        if !force, let last = lastInsightRefresh,
           Date().timeIntervalSince(last) < insightRefreshInterval { return }
        lastInsightRefresh = Date()
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
        try? d.write(to: socHistoryURL)
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
        try? data.write(to: historyCacheURL)
    }
}
