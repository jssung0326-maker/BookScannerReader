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

    @State private var showScanner = false
    @State private var pendingScans: [UIImage] = []
    @State private var processing = false
    @State private var processingMessage = "페이지 보정 · OCR · PDF 생성 중"
    @State private var errorMessage: String?

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

                    if captureMode == .doublePage {
                        pendingScans = images
                        splitPosition = autoDetectSplit
                            ? processor.suggestedSplitPosition(images[0])
                            : 0.5
                    } else {
                        Task { await process(images) }
                    }
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

                    var pair = processor.splitDoublePage(image, splitPosition: effectiveSplit)
                        .map { processor.correctPerspective($0) }

                    if readingOrder == .rightToLeft {
                        pair.reverse()
                    }
                    preparedPages.append(contentsOf: pair)
                } else {
                    preparedPages.append(processor.correctPerspective(image))
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

            var records: [PageRecord] = []
            var normalizedImages: [UIImage] = []

            for (index, image) in preparedPages.enumerated() {
                processingMessage = "페이지 \(index + 1) / \(preparedPages.count) 규격 통일 · OCR 중"

                let normalized = processor.normalize(image, profile: profile)
                let relativePath = try pageStore.saveJPEG(normalized, bookID: bookID, index: index)
                let recognized = (try? await ocr.recognize(image: normalized, languages: profile.ocrLanguages)) ?? ""

                records.append(
                    PageRecord(
                        index: index,
                        imageRelativePath: relativePath,
                        ocrText: recognized
                    )
                )
                normalizedImages.append(normalized)
            }

            processingMessage = "PDF 생성 중"
            try pageStore.savePages(records, bookID: bookID)
            let pdfURL = StoragePaths.pdfURL(bookID: bookID)
            try pdf.makePDF(images: normalizedImages, destination: pdfURL)

            let book = Book(
                id: bookID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "새 책" : title,
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
