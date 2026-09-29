import AVFoundation
import CoreLocation
import Foundation

@MainActor
final class BackgroundServices: NSObject, CLLocationManagerDelegate {
    var event: ((String, String) -> Void)?
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var healthTimer: Timer?
    private var observations: [NSObjectProtocol] = []
    private let location = CLLocationManager()
    private var audioWanted = false
    private var locationWanted = false
    private var interrupted = false
    private var recoveryAttempts = 0
    private var requestedAlways = false

    var audioRunning: Bool { engine.isRunning && player.isPlaying && audioWanted }
    var locationAuthorization: String {
        switch location.authorizationStatus {
        case .notDetermined: return "not determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "when in use"
        @unknown default: return "unknown"
        }
    }
    var audioRoute: String { AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ", ") }

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        location.distanceFilter = CLLocationDistanceMax
        location.pausesLocationUpdatesAutomatically = false
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            Task { @MainActor in self?.handleInterruption(type) }
        })
        observations.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.event?("audio_route", self.audioRoute) }
        })
        observations.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.event?("audio_media_reset", "Recreating audio engine")
                self.engine = AVAudioEngine(); self.player = AVAudioPlayerNode(); self.recoveryAttempts = 0
                if self.audioWanted && !self.interrupted { self.startAudio() }
            }
        })
    }

    func configure(audio: Bool, location enabledLocation: Bool) {
        if audio != audioWanted {
            audioWanted = audio
            recoveryAttempts = 0
            if audio { startAudio(); startHealthTimer() } else { stopAudio() }
        }
        if enabledLocation != locationWanted {
            locationWanted = enabledLocation
            if enabledLocation { enableLocation() } else {
                location.stopUpdatingLocation(); location.allowsBackgroundLocationUpdates = false
                event?("location_stopped", "User preference or session ended")
            }
        }
    }

    func stop() {
        audioWanted = false; locationWanted = false; interrupted = false
        stopAudio()
        location.stopUpdatingLocation(); location.allowsBackgroundLocationUpdates = false
        event?("background_services_stopped", "Audio and location stopped")
    }

    private func startAudio() {
        guard audioWanted, !interrupted, !audioRunning, recoveryAttempts < 3 else { return }
        recoveryAttempts += 1
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            player.stop(); engine.stop()
            engine = AVAudioEngine(); player = AVAudioPlayerNode()
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
            buffer.frameLength = 44_100
            if let channel = buffer.floatChannelData?[0] { channel.update(repeating: 0, count: Int(buffer.frameLength)) }
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.scheduleBuffer(buffer, at: nil, options: [.loops])
            try engine.start()
            player.play()
            recoveryAttempts = 0
            event?("audio_started", "Silent PCM loop; playback + mixWithOthers; route=\(audioRoute)")
        } catch {
            player.stop(); engine.stop()
            event?("audio_start_failed", "attempt=\(recoveryAttempts); \(error.localizedDescription)")
        }
    }

    private func stopAudio() {
        healthTimer?.invalidate(); healthTimer = nil
        player.stop(); engine.stop()
        do { try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]) }
        catch { event?("audio_deactivate_failed", error.localizedDescription) }
        event?("audio_stopped", "Silent player and engine stopped")
    }

    private func startHealthTimer() {
        healthTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.audioWanted, !self.interrupted, !self.audioRunning else { return }
                self.startAudio()
            }
        }
        healthTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handleInterruption(_ type: UInt?) {
        guard let type else { return }
        if type == AVAudioSession.InterruptionType.began.rawValue {
            interrupted = true
            event?("audio_interruption_began", "Sampling may be suspended; user audio preference preserved")
        } else {
            interrupted = false; recoveryAttempts = 0
            event?("audio_interruption_ended", "Resuming only if session still requests audio")
            if audioWanted { startAudio() }
        }
    }

    private func enableLocation() {
        guard locationWanted else { return }
        switch location.authorizationStatus {
        case .notDetermined:
            location.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if location.authorizationStatus == .authorizedWhenInUse && !requestedAlways {
                requestedAlways = true
                location.requestAlwaysAuthorization()
            }
            location.allowsBackgroundLocationUpdates = true
            location.startUpdatingLocation()
            event?("location_started", "Coarse 3km accuracy; authorization=\(locationAuthorization); coordinates are not recorded")
        case .denied, .restricted:
            event?("location_unavailable", locationAuthorization)
        @unknown default:
            event?("location_unavailable", "Unknown authorization")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        event?("location_authorization", locationAuthorization)
        if locationWanted { enableLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Record execution evidence without retaining location coordinates.
        event?("location_callback", "count=\(locations.count)")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        event?("location_error", error.localizedDescription)
    }
}
