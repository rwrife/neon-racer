import Combine

@MainActor
final class AccessibilitySettingsStore: ObservableObject {
    @Published var settings: AccessibilitySettings {
        didSet {
            persistence.save(settings)
        }
    }

    private let persistence: AccessibilitySettingsPersistence

    init(persistence: AccessibilitySettingsPersistence = AccessibilitySettingsPersistence()) {
        self.persistence = persistence
        settings = persistence.load()
    }
}
