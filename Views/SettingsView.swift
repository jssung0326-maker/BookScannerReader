import Foundation
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppPreferences.defaultCaptureMode) private var captureModeRaw = ScanProfile.CaptureMode.doublePage.rawValue
    @AppStorage(AppPreferences.defaultCaptureEngine) private var captureEngineRaw = ScanProfile.CaptureEngine.bookAutoCamera.rawValue
    @AppStorage(AppPreferences.defaultFitMode) private var fitModeRaw = ScanProfile.FitMode.aspectFit.rawValue
    @AppStorage(AppPreferences.defaultReadingOrder) private var readingOrderRaw = ScanProfile.ReadingOrder.leftToRight.rawValue
    @AppStorage(AppPreferences.defaultAutoCaptureEnabled) private var autoCaptureEnabled = true
    @AppStorage(AppPreferences.defaultMinimumLiveQualityScore) private var minimumQualityScore = 65
    @AppStorage(AppPreferences.defaultAutoCaptureDelay) private var autoCaptureDelay = 0.8
    @AppStorage(AppPreferences.defaultGeometryCorrectionEnabled) private var geometryCorrectionEnabled = true
    @AppStorage(AppPreferences.defaultTrimSpineShadow) private var trimSpineShadow = true
    @AppStorage(AppPreferences.defaultDewarpStrength) private var dewarpStrength = 0.35
    @AppStorage(AppPreferences.hasCompletedOnboarding) private var hasCompletedOnboarding = true

    var body: some View {
        NavigationStack {
            Form {
                Section("새 책 기본값") {
                    Picker("촬영", selection: $captureModeRaw) {
                        ForEach(ScanProfile.CaptureMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }

                    Picker("카메라", selection: $captureEngineRaw) {
                        ForEach(ScanProfile.CaptureEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine.rawValue)
                        }
                    }

                    Picker("페이지 맞춤", selection: $fitModeRaw) {
                        ForEach(ScanProfile.FitMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }

                    Picker("페이지 순서", selection: $readingOrderRaw) {
                        ForEach(ScanProfile.ReadingOrder.allCases) { order in
                            Text(order.displayName).tag(order.rawValue)
                        }
                    }
                }

                Section("자동 촬영") {
                    Toggle("자동 촬영", isOn: $autoCaptureEnabled)

                    Stepper("최소 품질 점수: \(minimumQualityScore)", value: $minimumQualityScore, in: 50...85, step: 5)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("안정 대기 시간")
                            Spacer()
                            Text(String(format: "%.1f초", autoCaptureDelay))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $autoCaptureDelay, in: 0.4...1.6, step: 0.1)
                    }
                }

                Section("페이지 보정") {
                    Toggle("원근 보정", isOn: $geometryCorrectionEnabled)
                    Toggle("제본부 그림자 제거", isOn: $trimSpineShadow)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("곡면 보정")
                            Spacer()
                            Text("\(Int((dewarpStrength * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $dewarpStrength, in: 0...1, step: 0.05)
                    }
                }

                Section("도움말") {
                    Button("첫 실행 안내 다시 보기") {
                        hasCompletedOnboarding = false
                        dismiss()
                    }
                }

                Section("앱 정보") {
                    LabeledContent("버전", value: appVersion)
                    Text("스캔한 책과 PDF는 앱의 Documents 영역에 저장되며 GitHub 소스 저장소에는 포함되지 않습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "10"
        return "\(version) (\(build))"
    }
}
