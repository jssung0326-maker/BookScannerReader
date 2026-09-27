import SwiftUI

struct BookReaderScreen: View {
    let book: Book

    @EnvironmentObject private var library: LibraryStore
    @StateObject private var speech = SpeechService()
    @State private var pages: [PageRecord] = []
    @State private var pageIndex = 0
    @State private var showPageManager = false
    @State private var showSearch = false

    private let pageStore = PageStore()

    var body: some View {
        Group {
            if let relative = effectiveBook.pdfRelativePath {
                PDFReaderView(
                    url: StoragePaths.bookDirectory(bookID: book.id).appendingPathComponent(relative),
                    pageIndex: $pageIndex
                )
            } else if !pages.isEmpty {
                scannedPageReader
            } else {
                ContentUnavailableView("읽을 페이지가 없습니다", systemImage: "book.closed")
            }
        }
        .navigationTitle(effectiveBook.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onDisappear(perform: saveReadingPosition)
        .toolbar {
            if !pages.isEmpty {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("책 내용 검색")

                    Menu {
                        Button {
                            showPageManager = true
                        } label: {
                            Label("페이지 관리", systemImage: "rectangle.stack.badge.gearshape")
                        }

                        Button {
                            if speech.isSpeaking {
                                speech.stop()
                            } else if pages.indices.contains(pageIndex) {
                                speech.speak(pages[pageIndex].ocrText)
                            }
                        } label: {
                            Label(speech.isSpeaking ? "읽기 중지" : "현재 페이지 읽어주기", systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showPageManager, onDismiss: reload) {
            PageManagerView(book: effectiveBook)
                .environmentObject(library)
        }
        .sheet(isPresented: $showSearch) {
            OCRSearchSheet(pages: pages) { selectedIndex in
                pageIndex = selectedIndex
                showSearch = false
            }
        }
    }

    private var effectiveBook: Book {
        library.book(with: book.id) ?? book
    }

    private var scannedPageReader: some View {
        VStack(spacing: 10) {
            if pages.indices.contains(pageIndex),
               let image = pageStore.image(bookID: book.id, relativePath: pages[pageIndex].imageRelativePath) {
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                    }
                }
            }

            HStack {
                Button("이전") { pageIndex = max(0, pageIndex - 1) }
                    .disabled(pageIndex == 0)
                Spacer()
                Text(pages.isEmpty ? "0 / 0" : "\(pageIndex + 1) / \(pages.count)")
                Spacer()
                Button("다음") { pageIndex = min(pages.count - 1, pageIndex + 1) }
                    .disabled(pages.isEmpty || pageIndex >= pages.count - 1)
            }
            .padding(.horizontal)
        }
    }

    private func reload() {
        pages = pageStore.loadPages(bookID: book.id)
        let savedIndex = library.book(with: book.id)?.currentPageIndex ?? book.currentPageIndex
        let maxIndex = pages.isEmpty
            ? max((library.book(with: book.id)?.pageCount ?? book.pageCount) - 1, 0)
            : max(pages.count - 1, 0)
        pageIndex = min(max(savedIndex, 0), maxIndex)
    }

    private func saveReadingPosition() {
        var updated = library.book(with: book.id) ?? book
        updated.currentPageIndex = max(pageIndex, 0)
        updated.updatedAt = .now
        library.update(updated)
    }
}

private struct OCRSearchSheet: View {
    let pages: [PageRecord]
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [PageRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return pages.filter { $0.ocrText.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "검색어를 입력하세요",
                        systemImage: "text.magnifyingglass",
                        description: Text("OCR로 인식된 전체 페이지에서 검색합니다.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { page in
                        Button {
                            onSelect(page.index)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("페이지 \(page.index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(snippet(for: page.ocrText, query: query))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
            }
            .navigationTitle("책 내용 검색")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "단어 또는 문장")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func snippet(for text: String, query: String) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = flattened.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(flattened.prefix(160))
        }

        let location = flattened.distance(from: flattened.startIndex, to: range.lowerBound)
        let startOffset = max(0, location - 60)
        let endOffset = min(flattened.count, location + query.count + 100)
        let start = flattened.index(flattened.startIndex, offsetBy: startOffset)
        let end = flattened.index(flattened.startIndex, offsetBy: endOffset)
        let prefix = startOffset > 0 ? "…" : ""
        let suffix = endOffset < flattened.count ? "…" : ""
        return prefix + String(flattened[start..<end]) + suffix
    }
}
