import Foundation

enum AppPreferences {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"

    static let defaultCaptureMode = "defaultCaptureMode"
    static let defaultCaptureEngine = "defaultCaptureEngine"
    static let defaultFitMode = "defaultFitMode"
    static let defaultReadingOrder = "defaultReadingOrder"
    static let defaultAutoCaptureEnabled = "defaultAutoCaptureEnabled"
    static let defaultMinimumLiveQualityScore = "defaultMinimumLiveQualityScore"
    static let defaultAutoCaptureDelay = "defaultAutoCaptureDelay"
    static let defaultGeometryCorrectionEnabled = "defaultGeometryCorrectionEnabled"
    static let defaultTrimSpineShadow = "defaultTrimSpineShadow"
    static let defaultDewarpStrength = "defaultDewarpStrength"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            defaultCaptureMode: ScanProfile.CaptureMode.doublePage.rawValue,
            defaultCaptureEngine: ScanProfile.CaptureEngine.bookAutoCamera.rawValue,
            defaultFitMode: ScanProfile.FitMode.aspectFit.rawValue,
            defaultReadingOrder: ScanProfile.ReadingOrder.leftToRight.rawValue,
            defaultAutoCaptureEnabled: true,
            defaultMinimumLiveQualityScore: 65,
            defaultAutoCaptureDelay: 0.8,
            defaultGeometryCorrectionEnabled: true,
            defaultTrimSpineShadow: true,
            defaultDewarpStrength: 0.35
        ])
    }
}
