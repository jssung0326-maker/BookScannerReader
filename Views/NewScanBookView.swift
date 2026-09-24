import SwiftUI
import UIKit

struct NewScanBookView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore

    @State private var title = "새 책"
    @State private var captureMode: ScanProfile.CaptureMode = .doublePage
    @State private var fitMode: ScanProfile.FitMode = .aspectFit
    @State private var showScanner = false
    @State private var processing = false
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
                        ForEach(ScanProfile.CaptureMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("페이지 맞춤", selection: $fitMode) {
                        ForEach(ScanProfile.FitMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text("첫 스캔 페이지의 가로:세로 비율을 이 책의 기준 규격으로 저장합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showScanner = true
                } label: {
                    Label("책 스캔 시작", systemImage: "camera.viewfinder")
                }
                .disabled(processing)
            }
            .navigationTitle("책 스캔")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
            .overlay {
                if processing {
                    ProgressView("페이지 보정 · OCR · PDF 생성 중")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .sheet(isPresented: $showScanner) {
                DocumentScannerView { images in
                    Task { await process(images) }
                } onCancel: {
                    showScanner = false
                } onError: { error in
                    errorMessage = error.localizedDescription
                    showScanner = false
                }
            }
            .alert("오류", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "알 수 없는 오류")
            }
        }
    }

    @MainActor
    private func process(_ scannedImages: [UIImage]) async {
        showScanner = false
        processing = true
        defer { processing = false }

        do {
            let bookID = UUID()
            var rawPages: [UIImage] = []
            for image in scannedImages {
                if captureMode == .doublePage {
                    rawPages.append(contentsOf: processor.splitDoublePage(image))
                } else {
                    rawPages.append(image)
                }
            }

            guard let first = rawPages.first else { return }
            var profile = processor.inferredProfile(from: first, captureMode: captureMode)
            profile.fitMode = fitMode

            var records: [PageRecord] = []
            var normalizedImages: [UIImage] = []

            for (index, image) in rawPages.enumerated() {
                let normalized = processor.normalize(image, profile: profile)
                let relativePath = try pageStore.saveJPEG(normalized, bookID: bookID, index: index)
                let recognized = (try? await ocr.recognize(image: normalized, languages: profile.ocrLanguages)) ?? ""
                records.append(PageRecord(index: index, imageRelativePath: relativePath, ocrText: recognized))
                normalizedImages.append(normalized)
            }

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
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
