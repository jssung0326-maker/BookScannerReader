import SwiftUI
import UIKit

struct PageManagerView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore

    @State private var pages: [PageRecord] = []
    @State private var showReplacementScanner = false
    @State private var replacingPageID: UUID?
    @State private var processing = false
    @State private var processingMessage = "페이지 정리 중"
    @State private var errorMessage: String?

    private let pageStore = PageStore()
    private let pdfService = PDFService()
    private let processor = ScanProcessingService()
    private let ocr = OCRService()

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    ContentUnavailableView(
                        "페이지가 없습니다",
                        systemImage: "rectangle.stack",
                        description: Text("스캔한 페이지가 있으면 여기에서 순서와 이미지를 관리할 수 있습니다.")
                    )
                } else {
                    List {
                        ForEach(pages) { page in
                            pageRow(page)
                        }
                        .onMove(perform: movePages)
                        .onDelete(perform: deletePages)
                    }
                }
            }
            .navigationTitle("페이지 관리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("완료") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .overlay {
                if processing {
                    ProgressView(processingMessage)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showReplacementScanner) {
                DocumentScannerView { images in
                    showReplacementScanner = false
                    guard let image = images.first, let pageID = replacingPageID else { return }
                    Task { await replacePage(pageID: pageID, with: image) }
                } onCancel: {
                    showReplacementScanner = false
                    replacingPageID = nil
                } onError: { error in
                    showReplacementScanner = false
                    replacingPageID = nil
                    errorMessage = error.localizedDescription
                }
            }
            .alert("페이지 처리 오류", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "알 수 없는 오류")
            }
        }
    }

    @ViewBuilder
    private func pageRow(_ page: PageRecord) -> some View {
        HStack(spacing: 14) {
            Group {
                if let image = pageStore.image(bookID: book.id, relativePath: page.imageRelativePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.15)
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 64, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                Text("페이지 \(page.index + 1)")
                    .font(.headline)

                if page.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("OCR 텍스트 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(page.ocrText.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Menu {
                Button {
                    replacingPageID = page.id
                    showReplacementScanner = true
                } label: {
                    Label("이 페이지만 다시 촬영", systemImage: "camera.rotate")
                }

                Button {
                    Task { await rotate(pageID: page.id, clockwise: false) }
                } label: {
                    Label("왼쪽으로 회전", systemImage: "rotate.left")
                }

                Button {
                    Task { await rotate(pageID: page.id, clockwise: true) }
                } label: {
                    Label("오른쪽으로 회전", systemImage: "rotate.right")
                }

                Button(role: .destructive) {
                    if let index = pages.firstIndex(where: { $0.id == page.id }) {
                        deletePages(at: IndexSet(integer: index))
                    }
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .disabled(processing)
        }
        .padding(.vertical, 3)
    }

    private func load() {
        pages = pageStore.loadPages(bookID: book.id)
        normalizeIndices()
    }

    private func normalizeIndices() {
        for index in pages.indices {
            pages[index].index = index
        }
    }

    private func movePages(from source: IndexSet, to destination: Int) {
        let preservedBookmarkIDs = bookmarkedPageIDs()
        pages.move(fromOffsets: source, toOffset: destination)
        normalizeIndices()
        Task {
            await persistAndRebuildPDF(
                message: "페이지 순서 변경 중",
                preservedBookmarkIDs: preservedBookmarkIDs
            )
        }
    }

    private func deletePages(at offsets: IndexSet) {
        let deleting = offsets.compactMap { index in
            pages.indices.contains(index) ? pages[index] : nil
        }
        let deletingIDs = Set(deleting.map(\.id))
        let preservedBookmarkIDs = bookmarkedPageIDs().subtracting(deletingIDs)

        do {
            for page in deleting {
                try pageStore.deleteImage(bookID: book.id, relativePath: page.imageRelativePath)
            }
            pages.remove(atOffsets: offsets)
            normalizeIndices()
            Task {
                await persistAndRebuildPDF(
                    message: "페이지 삭제 반영 중",
                    preservedBookmarkIDs: preservedBookmarkIDs
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func rotate(pageID: UUID, clockwise: Bool) async {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        guard let image = pageStore.image(bookID: book.id, relativePath: pages[index].imageRelativePath) else { return }

        processing = true
        processingMessage = "페이지 회전 · OCR 갱신 중"
        defer { processing = false }

        do {
            let rotated = rotate90(image, clockwise: clockwise)
            try pageStore.overwriteJPEG(rotated, bookID: book.id, relativePath: pages[index].imageRelativePath)
            let languages = book.scanProfile?.ocrLanguages ?? ["ko-KR", "en-US"]
            let recognized = try? await ocr.recognizeDetailed(image: rotated, languages: languages)
            pages[index].ocrText = recognized?.text ?? ""
            pages[index].ocrBlocks = recognized?.blocks ?? []
            normalizeIndices()
            try pageStore.savePages(pages, bookID: book.id)
            try rebuildPDF()
            updateBookMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func replacePage(pageID: UUID, with capturedImage: UIImage) async {
        replacingPageID = nil
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }

        processing = true
        processingMessage = "페이지 재촬영본 보정 · OCR 중"
        defer { processing = false }

        do {
            let profile = book.scanProfile ?? ScanProfile.initial
            let side = pageSide(for: pages[index].index, profile: profile)
            let prepared = processor.preparePage(
                capturedImage,
                side: side,
                geometryCorrectionEnabled: profile.geometryCorrectionEnabled,
                dewarpStrength: side == .single ? 0 : profile.dewarpStrength,
                trimSpineShadow: side == .single ? false : profile.trimSpineShadow
            )
            let normalized = processor.normalize(prepared, profile: profile)
            try pageStore.overwriteJPEG(normalized, bookID: book.id, relativePath: pages[index].imageRelativePath)
            let recognized = try? await ocr.recognizeDetailed(image: normalized, languages: profile.ocrLanguages)
            pages[index].ocrText = recognized?.text ?? ""
            pages[index].ocrBlocks = recognized?.blocks ?? []
            normalizeIndices()
            try pageStore.savePages(pages, bookID: book.id)
            try rebuildPDF()
            updateBookMetadata()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func persistAndRebuildPDF(
        message: String,
        preservedBookmarkIDs: Set<UUID>? = nil
    ) async {
        processing = true
        processingMessage = message
        defer { processing = false }

        do {
            normalizeIndices()
            try pageStore.savePages(pages, bookID: book.id)
            try rebuildPDF()
            updateBookMetadata(preservedBookmarkIDs: preservedBookmarkIDs)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildPDF() throws {
        let searchablePages: [PDFService.SearchablePage] = pages.compactMap { page in
            guard let image = pageStore.image(bookID: book.id, relativePath: page.imageRelativePath) else { return nil }
            return PDFService.SearchablePage(image: image, text: page.ocrText, blocks: page.ocrBlocks)
        }

        guard !searchablePages.isEmpty else {
            let url = StoragePaths.pdfURL(bookID: book.id)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }

        try pdfService.makeSearchablePDF(
            pages: searchablePages,
            destination: StoragePaths.pdfURL(bookID: book.id),
            title: book.title,
            author: book.author
        )
    }

    @MainActor
    private func updateBookMetadata(preservedBookmarkIDs: Set<UUID>? = nil) {
        var updated = library.book(with: book.id) ?? book
        updated.pageCount = pages.count
        updated.updatedAt = .now
        updated.currentPageIndex = min(updated.currentPageIndex, max(pages.count - 1, 0))
        updated.pdfRelativePath = pages.isEmpty ? nil : "book.pdf"

        if let preservedBookmarkIDs {
            updated.bookmarkedPageIndices = pages.enumerated().compactMap { index, page in
                preservedBookmarkIDs.contains(page.id) ? index : nil
            }
        } else {
            updated.bookmarkedPageIndices = updated.bookmarkedPageIndices.filter { $0 >= 0 && $0 < pages.count }
        }

        library.update(updated)
    }

    private func bookmarkedPageIDs() -> Set<UUID> {
        let indices = Set((library.book(with: book.id) ?? book).bookmarkedPageIndices)
        return Set(pages.enumerated().compactMap { index, page in
            indices.contains(index) ? page.id : nil
        })
    }

    private func pageSide(for index: Int, profile: ScanProfile) -> ScanProcessingService.PageSide {
        guard profile.captureMode == .doublePage else { return .single }
        let firstInPair = index.isMultiple(of: 2)
        switch profile.readingOrder {
        case .leftToRight:
            return firstInPair ? .left : .right
        case .rightToLeft:
            return firstInPair ? .right : .left
        }
    }

    private func rotate90(_ image: UIImage, clockwise: Bool) -> UIImage {
        let source = normalizedOrientation(image)
        let size = CGSize(width: source.size.height, height: source.size.width)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: clockwise ? .pi / 2 : -.pi / 2)
            source.draw(
                in: CGRect(
                    x: -source.size.width / 2,
                    y: -source.size.height / 2,
                    width: source.size.width,
                    height: source.size.height
                )
            )
        }
    }

    private func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
