import Foundation
import UIKit
import Darwin
import MonitorCore

struct MetricEvidence: Codable {
    var reading: MetricReading
    var source: String
    var scope: String
    var unit: String
    var raw: [String: Double]
}

struct InterfaceReading: Codable, Identifiable {
    var id: String
    var receivedBytes: UInt64
    var sentBytes: UInt64
    var rx: MetricReading
    var tx: MetricReading
}

struct DeviceSample: Codable {
    var sequence: Int
    var timestamp: Date
    var monotonicTime: Double
    var elapsedSeconds: Double
    var actualIntervalSeconds: Double?
    var cpu: MetricEvidence
    var ram: MetricEvidence
    var cpuTicks: [CPUTicks]?
    var interfaces: [InterfaceReading]
    var networkError: String?
    var batteryLevel: Double?
    var batteryState: String
    var thermalState: String
    var lowPowerMode: Bool
    var storageCapacityBytes: UInt64?
    var storageFreeBytes: UInt64?
    var ownCPUPercent: Double?
    var ownFootprintBytes: UInt64?
}

@MainActor
final class DeviceCollector {
    private var previousCPU: [CPUTicks]?
    private var previousInterfaces: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var previousTime: Double?
    private var previousOwnCPU: Double?

    func reset() {
        previousCPU = nil; previousInterfaces = [:]; previousTime = nil; previousOwnCPU = nil
    }

    func sample(sequence: Int, startedAt: Double) -> DeviceSample {
        let now = DeviceClock.now
        let interval = previousTime.map { now - $0 }
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let cpuResult = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        var ticks: [CPUTicks]?
        var cpuReading: MetricReading
        if cpuResult == KERN_SUCCESS, let info, cpuCount > 0, Int(infoCount) >= Int(cpuCount) * Int(CPU_STATE_MAX) {
            defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
            ticks = (0..<Int(cpuCount)).map { core in
                let offset = core * Int(CPU_STATE_MAX)
                func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[offset + Int(state)])) }
                return CPUTicks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM), nice: tick(CPU_STATE_NICE), idle: tick(CPU_STATE_IDLE))
            }
            cpuReading = TelemetryMath.cpuPercent(previous: previousCPU, current: ticks!)
        } else {
            if let info { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
            cpuReading = MetricReading(status: .unavailable, value: nil, reason: "host_processor_info returned \(cpuResult); cores=\(cpuCount), length=\(infoCount)")
        }
        previousCPU = ticks

        var vm = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let expectedVMCount = vmCount
        let vmResult = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        let capacity = ProcessInfo.processInfo.physicalMemory
        let ramReading: MetricReading
        var rawVM: [String: Double] = ["capacityBytes": Double(capacity)]
        if vmResult == KERN_SUCCESS, vmCount >= expectedVMCount, pageResult == KERN_SUCCESS {
            ramReading = TelemetryMath.occupiedRAM(capacity: capacity, freePages: UInt64(vm.free_count), pageSize: UInt64(pageSize))
            rawVM.merge(["pageSize": Double(pageSize), "freePages": Double(vm.free_count), "activePages": Double(vm.active_count), "inactivePages": Double(vm.inactive_count), "wiredPages": Double(vm.wire_count), "compressedPages": Double(vm.compressor_page_count)]) { _, new in new }
        } else {
            ramReading = MetricReading(status: .unavailable, value: nil, reason: "host_statistics64=\(vmResult), length=\(vmCount); host_page_size=\(pageResult)")
        }

        let network = readInterfaces(interval: interval)
        var usage = rusage()
        let usageResult = getrusage(RUSAGE_SELF, &usage)
        let ownTime = usageResult == 0 ? Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000 : nil
        var ownPercent: Double?
        if let ownTime, let previousOwnCPU, let interval, interval > 0, ownTime >= previousOwnCPU { ownPercent = 100 * (ownTime - previousOwnCPU) / interval }
        previousOwnCPU = ownTime

        var taskVM = task_vm_info_data_t()
        var taskCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let taskResult = withUnsafeMutablePointer(to: &taskVM) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(taskCount)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &taskCount) }
        }
        let storage = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        previousTime = now

        let device = UIDevice.current
        let battery = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        let batteryState: String
        switch device.batteryState { case .charging: batteryState = "charging"; case .full: batteryState = "full"; case .unplugged: batteryState = "unplugged"; default: batteryState = "unknown" }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState { case .nominal: thermal = "nominal"; case .fair: thermal = "fair"; case .serious: thermal = "serious"; case .critical: thermal = "critical"; @unknown default: thermal = "unknown" }

        return DeviceSample(sequence: sequence, timestamp: Date(), monotonicTime: now, elapsedSeconds: max(0, now - startedAt), actualIntervalSeconds: interval,
            cpu: MetricEvidence(reading: cpuReading, source: "host_processor_info / PROCESSOR_CPU_LOAD_INFO", scope: "device", unit: "%", raw: ["cores": Double(cpuCount), "resultCode": Double(cpuResult)]),
            ram: MetricEvidence(reading: ramReading, source: "host_statistics64 / HOST_VM_INFO64", scope: "device occupied RAM estimate", unit: "bytes", raw: rawVM),
            cpuTicks: ticks, interfaces: network.0, networkError: network.1, batteryLevel: battery, batteryState: batteryState, thermalState: thermal, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            storageCapacityBytes: (storage?[.systemSize] as? NSNumber)?.uint64Value, storageFreeBytes: (storage?[.systemFreeSize] as? NSNumber)?.uint64Value, ownCPUPercent: ownPercent, ownFootprintBytes: taskResult == KERN_SUCCESS ? taskVM.phys_footprint : nil)
    }

    private func readInterfaces(interval: Double?) -> ([InterfaceReading], String?) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { previousInterfaces = [:]; return ([], "getifaddrs errno=\(errno)") }
        defer { freeifaddrs(list) }
        var next = list
        var raw: [String: (rx: UInt64, tx: UInt64)] = [:]
        while let pointer = next {
            let item = pointer.pointee
            next = item.ifa_next
            guard let address = item.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK, let data = item.ifa_data else { continue }
            let name = String(cString: item.ifa_name)
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            let id = "\(name)#\(if_nametoindex(item.ifa_name))"
            raw[id] = (UInt64(counters.ifi_ibytes), UInt64(counters.ifi_obytes))
        }
        let readings = raw.keys.sorted().map { id -> InterfaceReading in
            let current = raw[id]!
            let previous = previousInterfaces[id]
            func rate(_ old: UInt64?, _ new: UInt64) -> MetricReading {
                guard let old, let interval, interval > 0 else { return MetricReading(status: .warmingUp, value: nil, reason: "New interface baseline") }
                guard let delta = CounterMath.delta(previous: old, current: new, allow32BitWrap: true) else { return MetricReading(status: .unavailable, value: nil, reason: "Interface counter reset") }
                return MetricReading(status: .ok, value: Double(delta) / interval, reason: nil)
            }
            return InterfaceReading(id: id, receivedBytes: current.rx, sentBytes: current.tx, rx: rate(previous?.rx, current.rx), tx: rate(previous?.tx, current.tx))
        }
        previousInterfaces = raw
        return (readings, readings.isEmpty ? "No AF_LINK interface counters exposed" : nil)
    }
}
