import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showNewScan = false
    @State private var showPDFImporter = false
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var importError: String?

    private let pdfService = PDFService()

    private var filteredBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return library.books }
        return library.books.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.author.localizedCaseInsensitiveContains(query)
        }
    }

    private var recentBooks: [Book] {
        library.books
            .filter { $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if library.books.isEmpty {
                    ContentUnavailableView(
                        "아직 책이 없습니다",
                        systemImage: "books.vertical",
                        description: Text("책을 스캔하거나 PDF를 가져오세요.")
                    )
                } else {
                    if !recentBooks.isEmpty {
                        Section("최근 읽은 책") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(recentBooks) { book in
                                        NavigationLink(value: book) {
                                            RecentBookCard(book: book)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 8, trailing: 12))
                        }
                    }

                    Section(searchText.isEmpty ? "전체 서재" : "검색 결과") {
                        if filteredBooks.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        } else {
                            ForEach(filteredBooks) { book in
                            NavigationLink(value: book) {
                                BookRow(book: book)
                            }
                            }
                            .onDelete(perform: removeFilteredBooks)
                        }
                    }
                }
            }
            .navigationTitle("내 서재")
            .searchable(text: $searchText, prompt: "제목 또는 저자 검색")
            .navigationDestination(for: Book.self) { book in
                BookReaderScreen(book: book)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("설정")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showNewScan = true
                        } label: {
                            Label("책 스캔", systemImage: "camera")
                        }

                        Button {
                            showPDFImporter = true
                        } label: {
                            Label("PDF 가져오기", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showNewScan) {
                NewScanBookView()
                    .environmentObject(library)
            }
            .fileImporter(
                isPresented: $showPDFImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                importPDF(result)
            }
            .alert("PDF 가져오기 실패", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(importError ?? "알 수 없는 오류")
            }
            .alert("저장 오류", isPresented: Binding(
                get: { library.lastErrorMessage != nil },
                set: { if !$0 { library.lastErrorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(library.lastErrorMessage ?? "알 수 없는 오류")
            }
        }
    }


    private func removeFilteredBooks(at offsets: IndexSet) {
        let ids = offsets.compactMap { index in
            filteredBooks.indices.contains(index) ? filteredBooks[index].id : nil
        }
        library.removeBooks(withIDs: Set(ids))
    }

    private func importPDF(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }

            let id = UUID()
            _ = try pdfService.copyImportedPDF(from: source, bookID: id)
            let importedURL = StoragePaths.pdfURL(bookID: id)
            let info = pdfService.documentInfo(at: importedURL)
            guard info.pageCount > 0 else {
                try? FileManager.default.removeItem(at: StoragePaths.bookDirectory(bookID: id))
                throw PDFImportError.emptyDocument
            }
            let fallbackTitle = source.deletingPathExtension().lastPathComponent
            let title = info.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let author = info.author?.trimmingCharacters(in: .whitespacesAndNewlines)
            let book = Book(
                id: id,
                title: (title?.isEmpty == false ? title! : fallbackTitle),
                author: author ?? "",
                pageCount: info.pageCount,
                pdfRelativePath: "book.pdf"
            )
            library.add(book)
        } catch {
            importError = error.localizedDescription
        }
    }
}

private enum PDFImportError: LocalizedError {
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "페이지가 없는 PDF는 가져올 수 없습니다."
        }
    }
}

private struct BookRow: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(book.title)
                .font(.headline)

            if !book.author.isEmpty {
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text("\(book.pageCount)페이지")
                if book.pageCount > 0 {
                    Text("·")
                    Text("최근 \(min(book.currentPageIndex + 1, book.pageCount))페이지")
                }
                if !book.bookmarkedPageIndices.isEmpty {
                    Text("·")
                    Label("\(book.bookmarkedPageIndices.count)", systemImage: "bookmark.fill")
                }
                if !book.readingNotes.isEmpty {
                    Text("·")
                    Label("\(book.readingNotes.count)", systemImage: "note.text")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if book.pageCount > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: book.readingProgress)
                    Text("\(Int((book.readingProgress * 100).rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RecentBookCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: book.pdfRelativePath == nil ? "book.closed" : "doc.richtext")
                .font(.title2)
                .frame(width: 42, height: 50)
                .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            Text(book.title)
                .font(.subheadline.bold())
                .lineLimit(2)
                .frame(height: 38, alignment: .topLeading)

            ProgressView(value: book.readingProgress)

            Text(book.pageCount > 0 ? "\(min(book.currentPageIndex + 1, book.pageCount)) / \(book.pageCount)" : "페이지 없음")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 145, alignment: .leading)
        .padding(10)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
