import SwiftUI

@main
struct NeonRacerApp: App {
    @StateObject private var accessibility = AccessibilitySettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(accessibility)
        }
    }
}
