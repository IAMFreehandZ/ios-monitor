import ActivityKit
import Foundation

struct MonitorAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var sequence: Int
        var sampledAt: Date
        var cpuPercent: Double?
        var ramGiB: Double?
        var phase: String
        var thermal: String
    }
    var sessionID: String
    var endsAt: Date
}
