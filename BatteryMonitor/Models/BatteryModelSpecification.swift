import Foundation

/// Apple 针对具体机型公开的电池与续航规格。
///
/// 这里保存的是发布规格，不是从当前电池电压反推的结果。数据层用 `hw.model`
/// 查表，UI 必须把它标成官方基准而不是本机实测值。
struct BatteryModelSpecification: Equatable, Sendable {
    let modelIdentifier: String
    let displayName: String
    let designEnergyWh: Double
    let officialWebHours: Double
    let officialVideoHours: Double
    let testCPUCoreCount: Int
    let testGPUCoreCount: Int
    let testMemoryGB: Int
    let testStorageGB: Int
    let sourceName: String
    let sourceURL: URL

    static let macBookAir13M4 = BatteryModelSpecification(
        modelIdentifier: "Mac16,12",
        displayName: "MacBook Air (13-inch, M4, 2025)",
        designEnergyWh: 53.8,
        officialWebHours: 15,
        officialVideoHours: 18,
        testCPUCoreCount: 10,
        testGPUCoreCount: 8,
        testMemoryGB: 16,
        testStorageGB: 256,
        sourceName: "Apple Support 122209",
        sourceURL: URL(string: "https://support.apple.com/122209")!
    )

    private static let catalog: [String: BatteryModelSpecification] = [
        macBookAir13M4.modelIdentifier: macBookAir13M4,
    ]

    static func lookup(modelIdentifier: String) -> BatteryModelSpecification? {
        catalog[modelIdentifier]
    }
}
