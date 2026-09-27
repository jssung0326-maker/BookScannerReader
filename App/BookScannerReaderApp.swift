import SwiftUI

@main
struct BookScannerReaderApp: App {
    @StateObject private var library = LibraryStore()
    @AppStorage(AppPreferences.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    init() {
        AppPreferences.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    LibraryView()
                        .environmentObject(library)
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
    }
}
