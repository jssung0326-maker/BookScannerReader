import SwiftUI
import PDFKit

struct BookReaderScreen: View {
    let book: Book

    @EnvironmentObject private var library: LibraryStore
    @StateObject private var speech = SpeechService()
    @State private var pages: [PageRecord] = []
    @State private var pageIndex = 0
    @State private var pdfLayout: PDFReaderLayout = .verticalContinuous
    @State private var showPageManager = false
    @State private var showSearch = false
    @State private var showBookmarks = false
    @State private var showPageJump = false

    private let pageStore = PageStore()

    var body: some View {
        Group {
            if let url = pdfURL {
                PDFReaderView(url: url, pageIndex: $pageIndex, layout: pdfLayout)
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
        .onChange(of: pageIndex) { _, _ in
            saveReadingPosition()
        }
        .toolbar {
            if hasReadableContent {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("책 내용 검색")

                    Button(action: toggleCurrentBookmark) {
                        Image(systemName: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(isCurrentPageBookmarked ? "현재 페이지 북마크 해제" : "현재 페이지 북마크")

                    Menu {
                        Section("읽기") {
                            Button {
                                showPageJump = true
                            } label: {
                                Label("페이지 이동", systemImage: "number.square")
                            }

                            Button {
                                showBookmarks = true
                            } label: {
                                Label("북마크 목록", systemImage: "bookmark.square")
                            }

                            Button {
                                if speech.isSpeaking {
                                    speech.stop()
                                } else {
                                    speech.speak(currentPageText())
                                }
                            } label: {
                                Label(
                                    speech.isSpeaking ? "읽기 중지" : "현재 페이지 읽어주기",
                                    systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2"
                                )
                            }
                        }

                        if pdfURL != nil {
                            Section("PDF 보기") {
                                Picker("보기 방식", selection: $pdfLayout) {
                                    ForEach(PDFReaderLayout.allCases) { layout in
                                        Label(layout.displayName, systemImage: layout.systemImage).tag(layout)
                                    }
                                }
                            }
                        }

                        if !pages.isEmpty {
                            Section("스캔 페이지") {
                                Button {
                                    showPageManager = true
                                } label: {
                                    Label("페이지 관리", systemImage: "rectangle.stack.badge.gearshape")
                                }
                            }
                        }

                        if let url = pdfURL {
                            Section("내보내기") {
                                ShareLink(item: url) {
                                    Label("PDF 공유 · 저장", systemImage: "square.and.arrow.up")
                                }
                            }
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
            ReaderSearchSheet(texts: searchableTexts()) { selectedIndex in
                pageIndex = selectedIndex
                showSearch = false
            }
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarkListSheet(
                pageIndices: effectiveBook.bookmarkedPageIndices,
                totalPages: totalPageCount
            ) { selectedIndex in
                pageIndex = selectedIndex
                showBookmarks = false
            }
        }
        .sheet(isPresented: $showPageJump) {
            PageJumpSheet(currentPage: pageIndex + 1, totalPages: totalPageCount) { selectedIndex in
                pageIndex = selectedIndex
                showPageJump = false
            }
        }
    }

    private var effectiveBook: Book {
        library.book(with: book.id) ?? book
    }

    private var pdfURL: URL? {
        guard let relative = effectiveBook.pdfRelativePath else { return nil }
        let url = StoragePaths.bookDirectory(bookID: book.id).appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var totalPageCount: Int {
        if !pages.isEmpty { return pages.count }
        if let url = pdfURL, let document = PDFDocument(url: url) { return document.pageCount }
        return effectiveBook.pageCount
    }

    private var hasReadableContent: Bool {
        totalPageCount > 0
    }

    private var isCurrentPageBookmarked: Bool {
        effectiveBook.bookmarkedPageIndices.contains(pageIndex)
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
                Text(totalPageCount == 0 ? "0 / 0" : "\(pageIndex + 1) / \(totalPageCount)")
                Spacer()
                Button("다음") { pageIndex = min(max(totalPageCount - 1, 0), pageIndex + 1) }
                    .disabled(totalPageCount == 0 || pageIndex >= totalPageCount - 1)
            }
            .padding(.horizontal)
        }
    }

    private func reload() {
        pages = pageStore.loadPages(bookID: book.id)
        let savedIndex = library.book(with: book.id)?.currentPageIndex ?? book.currentPageIndex
        pageIndex = min(max(savedIndex, 0), max(totalPageCount - 1, 0))
    }

    private func saveReadingPosition() {
        var updated = library.book(with: book.id) ?? book
        updated.currentPageIndex = min(max(pageIndex, 0), max(totalPageCount - 1, 0))
        updated.updatedAt = .now
        library.update(updated)
    }

    private func toggleCurrentBookmark() {
        guard totalPageCount > 0 else { return }
        var updated = library.book(with: book.id) ?? book
        var bookmarks = Set(updated.bookmarkedPageIndices)
        if bookmarks.contains(pageIndex) {
            bookmarks.remove(pageIndex)
        } else {
            bookmarks.insert(pageIndex)
        }
        updated.bookmarkedPageIndices = bookmarks.sorted()
        updated.updatedAt = .now
        library.update(updated)
    }

    private func currentPageText() -> String {
        if pages.indices.contains(pageIndex) {
            return pages[pageIndex].ocrText
        }
        guard let url = pdfURL,
              let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex)
        else { return "" }
        return page.string ?? ""
    }

    private func searchableTexts() -> [String] {
        if !pages.isEmpty {
            return pages.sorted(by: { $0.index < $1.index }).map(\.ocrText)
        }

        guard let url = pdfURL, let document = PDFDocument(url: url) else { return [] }
        return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }
}

private struct ReaderSearchSheet: View {
    private struct SearchResult: Identifiable {
        let pageIndex: Int
        let snippet: String
        var id: Int { pageIndex }
    }

    let texts: [String]
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return texts.enumerated().compactMap { index, text in
            guard text.localizedCaseInsensitiveContains(trimmed) else { return nil }
            return SearchResult(pageIndex: index, snippet: snippet(for: text, query: trimmed))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "검색어를 입력하세요",
                        systemImage: "text.magnifyingglass",
                        description: Text("스캔 OCR 또는 PDF의 텍스트에서 검색합니다.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { result in
                        Button {
                            onSelect(result.pageIndex)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("페이지 \(result.pageIndex + 1)")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(result.snippet)
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

private struct BookmarkListSheet: View {
    let pageIndices: [Int]
    let totalPages: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var validPages: [Int] {
        pageIndices.filter { $0 >= 0 && $0 < totalPages }.sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if validPages.isEmpty {
                    ContentUnavailableView(
                        "북마크가 없습니다",
                        systemImage: "bookmark",
                        description: Text("읽는 화면의 북마크 버튼으로 페이지를 저장할 수 있습니다.")
                    )
                } else {
                    List(validPages, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            Label("페이지 \(index + 1)", systemImage: "bookmark.fill")
                        }
                    }
                }
            }
            .navigationTitle("북마크")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}

private struct PageJumpSheet: View {
    let currentPage: Int
    let totalPages: Int
    let onGo: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pageText: String

    init(currentPage: Int, totalPages: Int, onGo: @escaping (Int) -> Void) {
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.onGo = onGo
        _pageText = State(initialValue: String(max(currentPage, 1)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("이동할 페이지") {
                    TextField("페이지 번호", text: $pageText)
                        .keyboardType(.numberPad)
                    Text("전체 \(totalPages)페이지")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("이동") {
                    guard let number = Int(pageText), totalPages > 0 else { return }
                    let safe = min(max(number, 1), totalPages)
                    onGo(safe - 1)
                }
                .disabled(Int(pageText) == nil || totalPages == 0)
            }
            .navigationTitle("페이지 이동")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
