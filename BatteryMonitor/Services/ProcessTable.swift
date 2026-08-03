import Foundation
import Darwin

/// 沙箱内可用的全进程枚举。
///
/// `proc_listpids(PROC_ALL_PIDS, 0, nil, 0)` 在 App Sandbox 里返回 0，
/// 但 `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)` 即使在明确拒绝 `process-info*`
/// 的沙箱里仍然返回完整进程表（实测 523/523）。两条路都不需要任何 entitlement，
/// 也不会触发任何授权弹窗。
///
/// 拿到 pid 之后能读到多少取决于 `proc_pidinfo`：同一用户的进程可读，root 进程
/// 即使完全不沙箱也一律失败（实测 pid 0 / 1 / WindowServer 全部返回 0）。所以
/// WindowServer、kernel_task 这类系统进程在不加特权 helper 的前提下永远拿不到 ——
/// 这是权限边界，不是实现缺陷，UI 侧需要照实说明而不是假装列表是全量。
enum ProcessTable {

    /// 只装值类型。`kinfo_proc` 里有 `struct proc *`、`struct session *` 等裸指针，
    /// 不是 `Sendable`，绝不能跨队列传递。
    struct Entry: Sendable, Equatable {
        let pid: Int32
        let ppid: Int32
        /// `p_comm`，内核截断到 16 字符。只在拿不到可执行文件路径时用作显示名。
        let comm: String
        /// 进程启动时间。用作 pid 回绕的判别键：macOS 的 pid 到 99999 会回绕，
        /// 只按 pid 缓存路径或历史曲线，会把新进程接到一个无关的旧进程身上。
        let startTime: TimeInterval
    }

    /// 单次采样的条数上限。本机常态 547 个进程，8192 留了约 15 倍余量，
    /// 同时挡住 sysctl 报回异常大的 size 时一次分配几百 MB。
    private static let maxProcessCount = 8192

    /// 少于这个条数就认为枚举不可用（正常机器不可能只有十几个进程）。
    /// `KERN_PROC_ALL` 在沙箱下可用是未文档化的行为，未来系统或审核环境一旦收紧，
    /// 调用方应当回落到 NSWorkspace 那条路，而不是显示一个空列表。
    static let minimumPlausibleCount = 20

    static func snapshot() -> [Entry] {
        guard let raw = enumerateRaw() else { return [] }
        return raw.map(entry(from:))
    }

    // MARK: - sysctl

    private static func enumerateRaw() -> [kinfo_proc]? {
        // mib 长度 4（末尾补 0）是 KERN_PROC 子操作的规定形式。
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        let stride = MemoryLayout<kinfo_proc>.stride

        // 两遍调用之间进程数会变，所以第二遍可能 ENOMEM。重试上限 4 次，
        // 不写 while true —— 一个进程正在疯狂 fork 时不能把采样线程卡死。
        for _ in 0..<4 {
            var needed = 0
            guard sysctl(&mib, u_int(mib.count), nil, &needed, nil, 0) == 0,
                  needed > 0 else { return nil }

            let capacity = min(needed / stride + 32, maxProcessCount)
            guard capacity > 0 else { return nil }

            var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            var size = capacity * stride
            let result = buffer.withUnsafeMutableBytes { bytes -> Int32 in
                sysctl(&mib, u_int(mib.count), bytes.baseAddress, &size, nil, 0)
            }
            if result == 0 {
                return Array(buffer.prefix(size / stride))
            }
            guard errno == ENOMEM else { return nil }
        }
        return nil
    }

    private static func entry(from proc: kinfo_proc) -> Entry {
        var bsd = proc.kp_proc
        // `p_comm` 是 17 元 CChar 元组（MAXCOMLEN + 1）。用 prefix(while:) 而不是
        // String(cString:)：内核只保证截断补 0，prefix 天然被 17 字节界限住；
        // 而 comm 可能含非 UTF-8 字节，String(decoding:as:) 会替换成 U+FFFD 而不是崩。
        let comm = withUnsafeBytes(of: &bsd.p_comm) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let started = proc.kp_proc.p_un.__p_starttime
        return Entry(
            pid: proc.kp_proc.p_pid,
            ppid: proc.kp_eproc.e_ppid,
            comm: comm,
            startTime: TimeInterval(started.tv_sec) + TimeInterval(started.tv_usec) / 1_000_000
        )
    }

    // MARK: - 归组

    /// 把每个进程归到「最近的祖先 GUI app」。找不到 app 祖先的进程自己就是一组
    /// （命令行工具、被 launchd/XPC 直接拉起来的 helper 都属于这种）。
    ///
    /// 实测边界：一台常态机器上 547 个进程里有 458 个 `ppid == 1`，因为它们是 launchd
    /// 或 XPC 拉起来的，不是父 app fork 出来的。所以 Chromium / Electron 系应用
    /// （浏览器、各类基于 Electron 的编辑器和客户端）能完整归并，而
    /// `com.apple.WebKit.*` 这类 Apple 自家 XPC helper 永远归不到父 app 下面。
    /// 这是 ppid 这个信号的固有上限。
    ///
    /// - Parameters:
    ///   - appPids: NSWorkspace 报出来的 GUI app 主进程 pid（`.regular` / `.accessory`）
    ///   - ownPid: 本进程 pid。它自己和它整棵子树都不会出现在结果里 ——
    ///             一个耗电分析工具把自己的采样开销算进排行毫无意义。
    /// - Returns: pid → 归组根 pid
    static func rollUp(entries: [Entry], appPids: Set<Int32>,
                       excludingSubtreeOf ownPid: Int32,
                       maxDepth: Int = 64) -> [Int32: Int32] {
        let parents = Dictionary(entries.map { ($0.pid, $0.ppid) },
                                 uniquingKeysWith: { first, _ in first })
        var roots: [Int32: Int32] = [:]
        roots.reserveCapacity(entries.count)

        for entry in entries {
            var current = entry.pid
            var visited: Set<Int32> = []
            var root: Int32?
            var belongsToOwnSubtree = false
            var depth = 0

            while depth < maxDepth {
                depth += 1
                if current == ownPid { belongsToOwnSubtree = true; break }
                if appPids.contains(current) { root = current; break }
                // 三重环保护：visited 挡住 ppid 成环，parent != current 挡住 pid 0
                // 的自环（真实存在），parent > 1 让 launchd 和 pid 0 不算 app 祖先。
                guard visited.insert(current).inserted,
                      let parent = parents[current],
                      parent > 1, parent != current else { break }
                current = parent
            }

            guard !belongsToOwnSubtree else { continue }
            roots[entry.pid] = root ?? entry.pid
        }
        return roots
    }
}
