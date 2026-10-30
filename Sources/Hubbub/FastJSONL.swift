import Foundation
import Darwin
import IOKit.ps

/// Duty-cycle limiter for background backfills: after each unit of work it sleeps long enough to hold CPU use near `duty`.
final class Pacer: @unchecked Sendable {
    private let duty: @Sendable () -> Double
    private var mark = DispatchTime.now()

    /// `duty` of 1 (or an absent pacer) means unthrottled.
    init(duty: @escaping @Sendable () -> Double) { self.duty = duty }

    /// Background policy: half a core normally, less on battery / Low Power Mode or while the popover is animating.
    static func background() -> Pacer { Pacer {
        var d = 0.5
        if ProcessInfo.processInfo.isLowPowerModeEnabled || PowerSource.onBattery { d = 0.2 }
        if Stage.popoverVisible { d = min(d, 0.25) }
        return d
    } }

    private var debt = 0.0

    func tick() {
        let now = DispatchTime.now()
        let worked = Double(now.uptimeNanoseconds &- mark.uptimeNanoseconds) / 1e9
        let d = max(0.05, min(1, duty()))
        if d < 1 {
            // Sub-millisecond naps are accumulated so fast chunks are still held to the duty cycle
            debt += worked * (1 - d) / d
            if debt >= 0.005 {
                let nap = min(1.0, debt)
                Thread.sleep(forTimeInterval: nap)
                debt = 0
            }
        }
        mark = DispatchTime.now()
    }
}

enum PowerSource {
    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        return type == kIOPMBatteryPowerKey
    }
}

/// Bounded-memory JSONL streaming. Reads with `pread` into one reusable buffer; lines the caller does not want are never copied or parsed.
enum JSONL {
    static let peek = 64

    struct Result { var endOffset: UInt64; var size: UInt64 }

    /// Calls `line` for every complete line at/after `offset` whose first bytes satisfy `wants`.
    /// `endOffset` is the start of the first incomplete trailing line (resume point for the next incremental scan).
    @discardableResult
    static func scan(path: String, from offset: UInt64 = 0, chunk: Int = 1 << 20, maxLine: Int = 256 << 20, uncached: Bool = false,
                     pacer: Pacer? = nil,
                     wants: (UnsafeRawBufferPointer) -> Bool,
                     line: (UnsafeRawBufferPointer) -> Void) -> Result? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { return nil }
        let size = UInt64(st.st_size)
        if uncached { _ = fcntl(fd, F_NOCACHE, 1) }
        guard offset < size else { return Result(endOffset: min(offset, size), size: size) }

        var cap = chunk
        var buf = UnsafeMutableRawPointer.allocate(byteCount: cap, alignment: 16)
        defer { buf.deallocate() }
        var filled = 0
        var base = offset            // file offset of buf[0]
        var committed = offset       // start of the first line not fully handled
        var readPos = offset
        var skipping = false

        while true {
            if filled == cap {
                if cap >= maxLine { skipping = true; filled = 0; base = readPos }
                else {
                    let bigger = UnsafeMutableRawPointer.allocate(byteCount: cap * 2, alignment: 16)
                    memcpy(bigger, buf, filled); buf.deallocate(); buf = bigger; cap *= 2
                }
            }
            let n = pread(fd, buf + filled, cap - filled, off_t(readPos))
            if n <= 0 { break }
            readPos += UInt64(n); filled += n
            var pos = 0
            while pos < filled {
                guard let nl = memchr(buf + pos, 10, filled - pos) else {
                    if skipping { pos = filled; base = readPos; filled = 0 }
                    else if filled - pos >= peek, !wants(UnsafeRawBufferPointer(start: buf + pos, count: peek)) {
                        skipping = true; pos = 0; filled = 0; base = readPos
                    }
                    break
                }
                let len = buf.distance(to: nl) - pos
                if skipping {
                    skipping = false
                } else if len > 0, wants(UnsafeRawBufferPointer(start: buf + pos, count: min(len, peek))) {
                    line(UnsafeRawBufferPointer(start: buf + pos, count: len))
                }
                pos += len + 1
                committed = base + UInt64(pos)
            }
            if !skipping, pos > 0, pos <= filled {
                if pos < filled { memmove(buf, buf + pos, filled - pos) }
                filled -= pos; base += UInt64(pos)
            }
            pacer?.tick()
        }
        return Result(endOffset: committed, size: size)
    }

    /// Cheap fingerprint of the first bytes of a file, to notice a log that was replaced rather than appended to.
    static func fingerprint(path: String) -> UInt64? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var b = [UInt8](repeating: 0, count: 256)
        let n = pread(fd, &b, 256, 0)
        guard n > 0 else { return 0 }
        var h: UInt64 = 1469598103934665603
        for i in 0..<n { h = (h ^ UInt64(b[i])) &* 1099511628211 }
        return h
    }

    static func hasPrefix(_ p: UnsafeRawBufferPointer, _ s: [UInt8]) -> Bool {
        p.count >= s.count && memcmp(p.baseAddress!, s, s.count) == 0
    }

    /// True when `needle` occurs within the first `limit` bytes.
    static func contains(_ p: UnsafeRawBufferPointer, _ needle: [UInt8], within limit: Int) -> Bool {
        let n = min(p.count, limit)
        guard n >= needle.count else { return false }
        return memmem(p.baseAddress!, n, needle, needle.count) != nil
    }

    /// Parses one line as a JSON object without copying the bytes.
    static func object(_ p: UnsafeRawBufferPointer) -> [String: Any]? {
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: p.baseAddress!), count: p.count, deallocator: .none)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// ISO-8601 parsing with per-thread formatters (formatter creation dominates naive per-line parsing).
enum FastDate {
    private final class Box { let frac: ISO8601DateFormatter; let plain = ISO8601DateFormatter()
        init() { frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds] } }
    private static func box() -> Box {
        let key = "hubbub.fastdate"
        if let b = Thread.current.threadDictionary[key] as? Box { return b }
        let b = Box(); Thread.current.threadDictionary[key] = b; return b
    }
    static func parseFractional(_ s: String) -> Date? { box().frac.date(from: s) }
    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        let b = box()
        return b.frac.date(from: s) ?? b.plain.date(from: s)
    }
}

/// Start-of-day lookups that avoid a Calendar call for every line of the same day.
struct DayCache {
    private var start = Date.distantFuture, end = Date.distantPast, key = 0.0
    mutating func startOfDay(_ d: Date) -> Double {
        if d >= start && d < end { return key }
        let cal = Calendar.current
        let s = cal.startOfDay(for: d)
        start = s; end = cal.date(byAdding: .day, value: 1, to: s) ?? s.addingTimeInterval(86400)
        key = s.timeIntervalSince1970
        return key
    }
}
