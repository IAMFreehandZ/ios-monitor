import SwiftUI

@main
struct MonitorApp: App {
    @StateObject private var session = SessionController()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { DashboardView(session: session) }
                    .tabItem { Label("Monitor", systemImage: "waveform.path.ecg") }
                NavigationStack { SessionsView(session: session) }
                    .tabItem { Label("Sessions", systemImage: "clock.arrow.circlepath") }
                NavigationStack { SettingsView(session: session) }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
    }
}
