import SwiftUI
import UIKit

struct NewScanBookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore

    @State private var title = "새 책"
    @State private var captureMode: ScanProfile.CaptureMode = .doublePage
    @State private var fitMode: ScanProfile.FitMode = .aspectFit
    @State private var readingOrder: ScanProfile.ReadingOrder = .leftToRight
    @State private var autoDetectSplit = true
    @State private var splitPosition = 0.5
    @State private var geometryCorrectionEnabled = true
    @State private var trimSpineShadow = true
    @State private var dewarpStrength = 0.35

    @State private var showScanner = false
    @State private var pendingScans: [UIImage] = []
    @State private var processing = false
    @State private var processingMessage = "페이지 보정 · OCR · PDF 생성 중"
    @State private var errorMessage: String?
    @State private var qualityWarning: String?
    @State private var qualityPendingScans: [UIImage] = []

    private let processor = ScanProcessingService()
    private let pageStore = PageStore()
    private let ocr = OCRService()
    private let pdf = PDFService()

    var body: some View {
        NavigationStack {
            Form {
                Section("책") {
                    TextField("책 제목", text: $title)
                }

                Section("스캔 방식") {
                    Picker("촬영", selection: $captureMode) {
                        ForEach(ScanProfile.CaptureMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Picker("페이지 맞춤", selection: $fitMode) {
                        ForEach(ScanProfile.FitMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    if captureMode == .doublePage {
                        Picker("페이지 순서", selection: $readingOrder) {
                            ForEach(ScanProfile.ReadingOrder.allCases) { order in
                                Text(order.displayName).tag(order)
                            }
                        }

                        Toggle("제본선 자동 찾기", isOn: $autoDetectSplit)
                    }

                    Text("첫 번째로 분리·보정된 페이지의 가로:세로 비율을 이 책의 기준 규격으로 저장하고, 이후 페이지를 같은 크기로 맞춥니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("페이지 보정") {
                    Toggle("페이지 경계 · 원근 자동 보정", isOn: $geometryCorrectionEnabled)

                    if captureMode == .doublePage {
                        Toggle("제본부 그림자 자동 제거", isOn: $trimSpineShadow)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("곡면 보정 강도")
                                Spacer()
                                Text("\(Int((dewarpStrength * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $dewarpStrength, in: 0...1, step: 0.05)
                        }

                        Text("곡면 보정은 제본부 가까운 글자가 눌려 보이는 현상을 완화하는 1차 보정입니다. 과하게 보이면 강도를 낮추세요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if captureMode == .doublePage, let firstScan = pendingScans.first {
                    Section("2페이지 분리 확인") {
                        SplitPreview(image: firstScan, splitPosition: splitPosition)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        if autoDetectSplit {
                            HStack {
                                Label("자동 검출", systemImage: "wand.and.stars")
                                Spacer()
                                Text("\(Int((splitPosition * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                            }
                            Text("각 촬영 사진마다 중앙 제본선 후보를 다시 찾아 좌우 페이지를 나눕니다.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("분리선 위치")
                                    Spacer()
                                    Text("\(Int((splitPosition * 100).rounded()))%")
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $splitPosition, in: 0.40...0.60, step: 0.005)
                            }
                            Text("빨간 선을 책의 가운데 제본선에 맞추세요. 이 위치를 모든 촬영 사진에 사용합니다.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Toggle("제본선 자동 찾기", isOn: Binding(
                            get: { autoDetectSplit },
                            set: { newValue in
                                autoDetectSplit = newValue
                                if newValue {
                                    splitPosition = processor.suggestedSplitPosition(firstScan)
                                }
                            }
                        ))

                        Button {
                            Task { await process(pendingScans) }
                        } label: {
                            Label("이 설정으로 분리해서 저장", systemImage: "square.split.2x1")
                        }
                        .disabled(processing)

                        Button(role: .destructive) {
                            pendingScans.removeAll()
                            showScanner = true
                        } label: {
                            Label("다시 촬영", systemImage: "arrow.clockwise.camera")
                        }
                        .disabled(processing)
                    }
                } else {
                    Section {
                        Button {
                            pendingScans.removeAll()
                            showScanner = true
                        } label: {
                            Label("책 스캔 시작", systemImage: "camera.viewfinder")
                        }
                        .disabled(processing)
                    }
                }
            }
            .navigationTitle("책 스캔")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .overlay {
                if processing {
                    ProgressView(processingMessage)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding()
                }
            }
            .sheet(isPresented: $showScanner) {
                DocumentScannerView { images in
                    showScanner = false
                    guard !images.isEmpty else { return }
                    handleCaptured(images)
                } onCancel: {
                    showScanner = false
                } onError: { error in
                    errorMessage = error.localizedDescription
                    showScanner = false
                }
            }
            .alert("오류", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "알 수 없는 오류")
            }
            .confirmationDialog(
                "촬영 품질 확인",
                isPresented: Binding(
                    get: { qualityWarning != nil },
                    set: { if !$0 { qualityWarning = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("계속 진행") {
                    let images = qualityPendingScans
                    qualityPendingScans.removeAll()
                    qualityWarning = nil
                    acceptCaptured(images)
                }
                Button("다시 촬영", role: .destructive) {
                    qualityPendingScans.removeAll()
                    qualityWarning = nil
                    showScanner = true
                }
                Button("취소", role: .cancel) {
                    qualityPendingScans.removeAll()
                    qualityWarning = nil
                }
            } message: {
                Text(qualityWarning ?? "")
            }
        }
    }

    @MainActor
    private func handleCaptured(_ images: [UIImage]) {
        var warnings: [String] = []
        for (index, image) in images.enumerated() {
            let report = processor.qualityReport(image)
            if !report.isAcceptable {
                warnings.append("촬영본 \(index + 1):\n\(report.summary)")
            }
        }

        if warnings.isEmpty {
            acceptCaptured(images)
        } else {
            qualityPendingScans = images
            qualityWarning = warnings.joined(separator: "\n\n")
        }
    }

    @MainActor
    private func acceptCaptured(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        if captureMode == .doublePage {
            pendingScans = images
            splitPosition = autoDetectSplit
                ? processor.suggestedSplitPosition(images[0])
                : 0.5
        } else {
            Task { await process(images) }
        }
    }

    @MainActor
    private func process(_ scannedImages: [UIImage]) async {
        processing = true
        processingMessage = "페이지 분리 및 원근 보정 중"
        defer { processing = false }

        do {
            let bookID = UUID()
            var preparedPages: [UIImage] = []

            for (captureIndex, image) in scannedImages.enumerated() {
                processingMessage = "촬영본 \(captureIndex + 1) / \(scannedImages.count) 분리 · 보정 중"

                if captureMode == .doublePage {
                    let effectiveSplit = autoDetectSplit
                        ? processor.suggestedSplitPosition(image)
                        : splitPosition

                    let split = processor.splitDoublePage(image, splitPosition: effectiveSplit)
                    var pair: [UIImage] = []

                    if split.indices.contains(0) {
                        pair.append(
                            processor.preparePage(
                                split[0],
                                side: .left,
                                geometryCorrectionEnabled: geometryCorrectionEnabled,
                                dewarpStrength: dewarpStrength,
                                trimSpineShadow: trimSpineShadow
                            )
                        )
                    }
                    if split.indices.contains(1) {
                        pair.append(
                            processor.preparePage(
                                split[1],
                                side: .right,
                                geometryCorrectionEnabled: geometryCorrectionEnabled,
                                dewarpStrength: dewarpStrength,
                                trimSpineShadow: trimSpineShadow
                            )
                        )
                    }

                    if readingOrder == .rightToLeft {
                        pair.reverse()
                    }
                    preparedPages.append(contentsOf: pair)
                } else {
                    preparedPages.append(
                        processor.preparePage(
                            image,
                            side: .single,
                            geometryCorrectionEnabled: geometryCorrectionEnabled,
                            dewarpStrength: 0,
                            trimSpineShadow: false
                        )
                    )
                }
            }

            guard let first = preparedPages.first else { return }

            var profile = processor.inferredProfile(from: first, captureMode: captureMode)
            profile.fitMode = fitMode
            profile.autoDetectSplit = autoDetectSplit
            profile.splitPosition = captureMode == .doublePage
                ? (autoDetectSplit ? processor.suggestedSplitPosition(scannedImages[0]) : splitPosition)
                : 0.5
            profile.readingOrder = readingOrder
            profile.geometryCorrectionEnabled = geometryCorrectionEnabled
            profile.dewarpStrength = captureMode == .doublePage ? dewarpStrength : 0
            profile.trimSpineShadow = captureMode == .doublePage ? trimSpineShadow : false

            var records: [PageRecord] = []
            var normalizedImages: [UIImage] = []

            for (index, image) in preparedPages.enumerated() {
                processingMessage = "페이지 \(index + 1) / \(preparedPages.count) 규격 통일 · OCR 중"

                let normalized = processor.normalize(image, profile: profile)
                let relativePath = try pageStore.saveJPEG(normalized, bookID: bookID, index: index)
                let recognized = try? await ocr.recognizeDetailed(image: normalized, languages: profile.ocrLanguages)

                records.append(
                    PageRecord(
                        index: index,
                        imageRelativePath: relativePath,
                        ocrText: recognized?.text ?? "",
                        ocrBlocks: recognized?.blocks ?? []
                    )
                )
                normalizedImages.append(normalized)
            }

            processingMessage = "검색 가능한 PDF 생성 중"
            try pageStore.savePages(records, bookID: bookID)
            let pdfURL = StoragePaths.pdfURL(bookID: bookID)
            let searchablePages = zip(normalizedImages, records).map { image, record in
                PDFService.SearchablePage(image: image, text: record.ocrText, blocks: record.ocrBlocks)
            }
            let bookTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "새 책" : title
            try pdf.makeSearchablePDF(
                pages: searchablePages,
                destination: pdfURL,
                title: bookTitle
            )

            let book = Book(
                id: bookID,
                title: bookTitle,
                pageCount: records.count,
                pdfRelativePath: "book.pdf",
                scanProfile: profile
            )

            library.add(book)
            pendingScans.removeAll()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SplitPreview: View {
    let image: UIImage
    let splitPosition: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    GeometryReader { proxy in
                        Path { path in
                            let x = proxy.size.width * CGFloat(splitPosition)
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        }
                        .stroke(.red, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    }
                }
        }
        .accessibilityLabel("두 페이지 분리 미리보기")
    }
}
