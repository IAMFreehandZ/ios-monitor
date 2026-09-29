import Darwin

// Continuous Mach time includes device sleep and ignores wall-clock changes.
enum DeviceClock {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    static var now: Double { Double(mach_continuous_time()) * secondsPerTick }
}
