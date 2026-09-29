import Foundation
import UIKit
import Darwin
import MonitorCore

struct SessionMetadata: Codable {
    var id: UUID
    var startedAt: Date
    var durationSeconds: Double
    var audioEnabled: Bool
    var locationEnabled: Bool
    var deviceModel: String
    var operatingSystem: String
    var sourceCommit: String
    var appVersion: String
    var buildNumber: String
    var bundleIdentifier: String
    var extensionIdentifierBeforeSigning: String
    var xcodeVersion: String
    var sdk: String
    var locationAuthorization: String
    var initialAudioRoute: String
    var initialLowPowerMode: Bool
    var backgroundRefreshStatus: String
    var signingMethod: String
}

struct RecordingEvent: Codable {
    var timestamp: Date
    var elapsedSeconds: Double
    var name: String
    var detail: String
}

struct RecordingLine: Codable {
    var kind: String
    var sample: DeviceSample?
    var event: RecordingEvent?
}

struct RecordingSummary: Codable {
    var sessionID: UUID
    var endedAt: Date
    var stopReason: String
    var recordingDurationSeconds: Double
    var tailUnknown: Bool
    var sampleCount: Int
    var validCPUSamples: Int
    var validRAMSamples: Int
    var continuity: ContinuitySummary
    var lastSampleAt: Date?
    var note: String
}

struct SavedSession: Identifiable {
    var id: String
    var folder: URL
    var summary: RecordingSummary?
    var files: [URL] { ["metadata.json", "recording.jsonl", "summary.json"].map { folder.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) } }
}

final class SessionRecorder {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Sessions", isDirectory: true)
    }
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    static func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
    let folder: URL
    private var handle: FileHandle?
    private var elapsedTimes: [Double] = []
    private var validCPU = 0
    private var validRAM = 0
    private var lastSampleAt: Date?
    private let id: UUID

    init(metadata: SessionMetadata) throws {
        id = metadata.id
        folder = Self.root.appendingPathComponent(metadata.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder().encode(metadata).write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)
        let log = folder.appendingPathComponent("recording.jsonl")
        guard FileManager.default.createFile(atPath: log.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        handle = try FileHandle(forWritingTo: log)
    }

    func append(_ sample: DeviceSample) throws {
        try write(RecordingLine(kind: "sample", sample: sample, event: nil))
        elapsedTimes.append(sample.elapsedSeconds)
        if sample.cpu.reading.status == .ok { validCPU += 1 }
        if sample.ram.reading.status == .ok { validRAM += 1 }
        lastSampleAt = sample.timestamp
    }

    func event(name: String, detail: String, elapsed: Double) throws {
        try write(RecordingLine(kind: "event", sample: nil, event: RecordingEvent(timestamp: Date(), elapsedSeconds: elapsed, name: name, detail: detail)))
    }

    private func write(_ line: RecordingLine) throws {
        var data = try Self.encoder().encode(line)
        data.append(0x0A)
        if let handle {
            try handle.write(contentsOf: data)
        } else {
            let lateHandle = try FileHandle(forWritingTo: folder.appendingPathComponent("recording.jsonl"))
            defer { try? lateHandle.close() }
            try lateHandle.seekToEnd()
            try lateHandle.write(contentsOf: data)
        }
    }

    func finish(reason: String, duration: Double) throws -> RecordingSummary {
        try handle?.synchronize()
        try handle?.close(); handle = nil
        let summary = RecordingSummary(sessionID: id, endedAt: Date(), stopReason: reason, recordingDurationSeconds: duration, tailUnknown: false, sampleCount: elapsedTimes.count, validCPUSamples: validCPU, validRAMSamples: validRAM, continuity: ContinuitySummary(elapsedTimes: elapsedTimes, recordingDuration: duration), lastSampleAt: lastSampleAt, note: "Actual device counter access and background behavior require user review. Activity submission completion is not proof of rendering.")
        try Self.encoder().encode(summary).write(to: folder.appendingPathComponent("summary.json"), options: .atomic)
        return summary
    }

    deinit { try? handle?.close() }

    static func recoverInterrupted() {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for folder in folders {
            let summaryURL = folder.appendingPathComponent("summary.json")
            guard !FileManager.default.fileExists(atPath: summaryURL.path),
                  let metadataData = try? Data(contentsOf: folder.appendingPathComponent("metadata.json")),
                  let metadata = try? decoder().decode(SessionMetadata.self, from: metadataData) else { continue }
            let log = (try? Data(contentsOf: folder.appendingPathComponent("recording.jsonl"))) ?? Data()
            var samples: [DeviceSample] = []
            for line in log.split(separator: 0x0A) {
                if let record = try? decoder().decode(RecordingLine.self, from: Data(line)), let sample = record.sample { samples.append(sample) }
            }
            let duration = samples.last?.elapsedSeconds ?? 0
            let summary = RecordingSummary(sessionID: metadata.id, endedAt: Date(), stopReason: "interrupted_on_previous_launch", recordingDurationSeconds: duration, tailUnknown: true, sampleCount: samples.count, validCPUSamples: samples.filter { $0.cpu.reading.status == .ok }.count, validRAMSamples: samples.filter { $0.ram.reading.status == .ok }.count, continuity: ContinuitySummary(elapsedTimes: samples.map(\.elapsedSeconds), recordingDuration: duration), lastSampleAt: samples.last?.timestamp, note: "Partial recording recovered on relaunch. Termination time and the unrecorded tail are unknown; continuity is for the observed prefix only and is not a qualification result.")
            try? encoder().encode(summary).write(to: summaryURL, options: .atomic)
        }
    }

    static func saved() -> [SavedSession] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return folders.map { folder in
            let summary = (try? Data(contentsOf: folder.appendingPathComponent("summary.json"))).flatMap { try? decoder().decode(RecordingSummary.self, from: $0) }
            return SavedSession(id: folder.lastPathComponent, folder: folder, summary: summary)
        }.sorted { ($0.summary?.endedAt ?? .distantPast) > ($1.summary?.endedAt ?? .distantPast) }
    }

    static func deviceModel() -> String {
        var system = utsname(); uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        return withUnsafePointer(to: &system.machine) { $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) } }
    }
}
